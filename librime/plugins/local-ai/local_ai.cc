// Local-only, asynchronous completion. No Rime objects are touched by workers.
#include <windows.h>
#include <winhttp.h>
#include <yaml-cpp/yaml.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <rime_api.h>
#include <rime/candidate.h>
#include <rime/context.h>
#include <rime/engine.h>
#include <rime/key_event.h>
#include <rime/processor.h>
#include <rime/registry.h>
#include <rime/schema.h>
#include <rime/segmentation.h>
#include <rime/segmentor.h>
#include <rime/translation.h>
#include <rime/translator.h>

namespace local_ai {
using namespace rime;
using Clock = std::chrono::steady_clock;
constexpr char marker[] = "~ai";
struct Result {
  std::mutex mutex;
  uint64_t generation = 0;
  string status = "idle", text;
};
struct Job {
  std::shared_ptr<Result> result;
  uint64_t generation;
  string prefix, model;
  int port;
};
struct HttpHandle {
  HINTERNET handle;
  explicit HttpHandle(HINTERNET h) : handle(h) {}
  ~HttpHandle() { if (handle) WinHttpCloseHandle(handle); }
  operator HINTERNET() const { return handle; }
};
string Quote(const string& value) {
  string out = "\"";
  for (unsigned char c : value) {
    if (c == '"' || c == '\\') { out += '\\'; out += c; }
    else if (c < 0x20) {
      const char* hex = "0123456789abcdef";
      out += "\\u00"; out += hex[c >> 4]; out += hex[c & 15];
    } else out += c;
  }
  return out + '"';
}
string Complete(const Job& job) {
  HttpHandle session(WinHttpOpen(L"RimeLocalAI/0.1", WINHTTP_ACCESS_TYPE_NO_PROXY,
                                 WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
  if (!session) throw std::runtime_error("http_init_error");
  WinHttpSetTimeouts(session, 500, 500, 1500, 1500);
  HttpHandle connection(WinHttpConnect(session, L"127.0.0.1", job.port, 0));
  if (!connection) throw std::runtime_error("connection_error");
  HttpHandle request(WinHttpOpenRequest(connection, L"POST", L"/v1/chat/completions",
      nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0));
  if (!request) throw std::runtime_error("request_error");
  if (!WinHttpSetTimeouts(request, 500, 500, 1500, 1500)) throw std::runtime_error("timeout_config_error");
  DWORD redirect = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
  WinHttpSetOption(request, WINHTTP_OPTION_REDIRECT_POLICY, &redirect, sizeof(redirect));
  const string payload = "{\"model\":" + Quote(job.model) +
      ",\"messages\":[{\"role\":\"system\",\"content\":" +
      Quote("你是输入法的短句补全器。根据用户给出的前文，只输出紧接其后的短续写，不要重复前文，不要解释，不要使用引号。最多续写30个汉字。") +
      "},{\"role\":\"user\",\"content\":" + Quote(job.prefix) +
      "}],\"max_tokens\":64,\"temperature\":0.2,\"stream\":false,"
      "\"chat_template_kwargs\":{\"enable_thinking\":false}}";
  if (!WinHttpSendRequest(request, L"Content-Type: application/json\r\n", -1,
      const_cast<char*>(payload.data()), static_cast<DWORD>(payload.size()),
      static_cast<DWORD>(payload.size()), 0) ||
      !WinHttpReceiveResponse(request, nullptr)) throw std::runtime_error("unavailable_or_timeout");
  DWORD status = 0, size = sizeof(status);
  if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX) || status != 200)
    throw std::runtime_error("http_error");
  string body;
  const auto deadline = Clock::now() + std::chrono::seconds(3);
  char buffer[4096];
  for (;;) {
    DWORD read = 0;
    if (Clock::now() > deadline) throw std::runtime_error("timeout");
    if (!WinHttpReadData(request, buffer, sizeof(buffer), &read)) throw std::runtime_error("read_error");
    if (!read) break;
    body.append(buffer, read);
    if (body.size() > 32768) throw std::runtime_error("response_too_large");
  }
  auto json = YAML::Load(body); // JSON is a subset supported by yaml-cpp.
  string text = json["choices"][0]["message"]["content"].as<string>();
  if (text.empty() || text.size() > 512 ||
      !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0))
    throw std::runtime_error("invalid_completion");
  for (unsigned char c : text) if (c < 0x20 || c == 0x7f) throw std::runtime_error("invalid_completion");
  if (text.find("<think>") != string::npos || text.find("</think>") != string::npos)
    throw std::runtime_error("reasoning_not_supported");
  if (text.compare(0, job.prefix.size(), job.prefix) == 0) text.erase(0, job.prefix.size());
  if (text.empty()) throw std::runtime_error("empty_completion");
  return text;
}
// A single bounded worker for the process: no inference on a key-event thread.
class Worker {
 public:
  Worker() : thread_([this] { Run(); }) {}
  ~Worker() {
    { std::lock_guard<std::mutex> lock(mutex_); stop_ = true; }
    cv_.notify_one();
    thread_.join();
  }
  bool Submit(Job job) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (busy_ || stop_) return false;
    job_ = std::make_unique<Job>(std::move(job)); busy_ = true;
    cv_.notify_one(); return true;
  }
 private:
  void Run() {
    for (;;) {
      std::unique_ptr<Job> job;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this] { return stop_ || job_; });
        if (stop_) return;
        job = std::move(job_);
      }
      string text, status = "ready";
      try { text = Complete(*job); }
      catch (const std::exception&) { status = "error"; }
      catch (...) { status = "error"; }
      {
        std::lock_guard<std::mutex> lock(job->result->mutex);
        if (job->result->generation == job->generation) {
          job->result->text = std::move(text); job->result->status = status;
        }
      }
      { std::lock_guard<std::mutex> lock(mutex_); busy_ = false; }
    }
  }
  std::mutex mutex_; std::condition_variable cv_;
  std::unique_ptr<Job> job_; bool busy_ = false, stop_ = false;
  std::thread thread_;
};
std::unique_ptr<Worker> worker;

class AiProcessor : public Processor {
 public:
  explicit AiProcessor(const Ticket& ticket) : Processor(ticket), result_(std::make_shared<Result>()) {
    engine_->schema()->config()->GetInt("local_ai/port", &port_);
    engine_->schema()->config()->GetString("local_ai/model", &model_);
    if (port_ < 1 || port_ > 65535) port_ = 18080;
  }
  ~AiProcessor() override { Cancel(); }
  ProcessResult ProcessKeyEvent(const KeyEvent& key) override {
    auto* ctx = engine_->context();
    if (key.release()) return kNoop;
    const bool trigger = key.ctrl() && !key.alt() && !key.super() && !key.shift() && key.keycode() == XK_Tab;
    if (ctx->get_option("ascii_mode")) { Cancel(); return kNoop; }
    if (preview_) {
      if (ctx->input() != marker || ctx->get_property("_local_ai_text").empty()) {
        preview_ = false; Cancel();
      } else if (!key.ctrl() && !key.alt() && !key.super() &&
          (key.keycode() == XK_Tab || key.keycode() == XK_space || key.keycode() == XK_Return)) {
        ctx->Commit(); ctx->set_property("_local_ai_text", ""); preview_ = false; Cancel();
        return kAccepted;
      } else {
        preview_ = false;
        ctx->set_property("_local_ai_text", ""); ctx->set_input(original_input_); Cancel();
        if (key.keycode() == XK_Escape) return kAccepted;
      }
    }
    if (!trigger) {
      // Any edit/navigation invalidates the snapshot. Nothing is auto-committed.
      if (key.keycode() != XK_Control_L && key.keycode() != XK_Control_R &&
          key.keycode() != XK_Shift_L && key.keycode() != XK_Shift_R) {
        Cancel(); ctx->set_property("local_ai_status", "idle");
        if (!ctx->composition().empty()) ctx->composition().back().prompt.clear();
      }
      return kNoop;
    }
    string status, text;
    {
      std::lock_guard<std::mutex> lock(result_->mutex);
      status = result_->status; text = result_->text;
    }
    if ((status == "pending" || status == "ready") &&
        (ctx->input() != original_input_ || ctx->GetCommitText() != original_text_ ||
         Clock::now() - requested_ > std::chrono::seconds(15))) {
      Cancel(); status = "idle";
    }
    if (status == "pending") {
      ctx->set_property("local_ai_status", "pending");
      if (!ctx->composition().empty()) ctx->composition().back().prompt = "〔AI处理中，再按Ctrl+Tab查看〕";
      return kAccepted;
    }
    if (status == "ready") {
      ctx->set_property("_local_ai_text", original_text_ + text);
      preview_ = true; ctx->set_input(marker);
      ctx->set_property("local_ai_status", "preview");
      return kAccepted;
    }
    if (status == "error") {
      Cancel(); ctx->set_property("local_ai_status", "unavailable");
      if (!ctx->composition().empty()) ctx->composition().back().prompt = "〔AI不可用，可继续正常输入〕";
      return kAccepted;
    }
    if (!ctx->IsComposing() || !ctx->GetSelectedCandidate()) {
      ctx->set_property("local_ai_status", "compose_first"); return kAccepted;
    }
    original_input_ = ctx->input(); original_text_ = ctx->GetCommitText();
    if (original_text_.empty() || original_text_.size() > 1024) {
      ctx->set_property("local_ai_status", "input_too_long"); return kAccepted;
    }
    uint64_t generation;
    {
      std::lock_guard<std::mutex> lock(result_->mutex);
      generation = ++result_->generation; result_->status = "pending"; result_->text.clear();
    }
    requested_ = Clock::now();
    if (!worker || !worker->Submit({result_, generation, original_text_, model_, port_})) {
      Cancel(); ctx->set_property("local_ai_status", "busy");
    } else {
      ctx->set_property("local_ai_status", "pending");
      if (!ctx->composition().empty()) ctx->composition().back().prompt = "〔AI处理中，再按Ctrl+Tab查看〕";
    }
    return kAccepted;
  }
 private:
  void Cancel() {
    std::lock_guard<std::mutex> lock(result_->mutex);
    ++result_->generation; result_->status = "idle"; result_->text.clear();
  }
  std::shared_ptr<Result> result_;
  string original_input_, original_text_, model_ = "qwen3.5-0.8b";
  int port_ = 18080; bool preview_ = false; Clock::time_point requested_;
};
class AiSegmentor : public Segmentor {
 public:
  explicit AiSegmentor(const Ticket& ticket) : Segmentor(ticket) {}
  bool Proceed(Segmentation* segmentation) override {
    if (segmentation->input() != marker || engine_->context()->get_property("_local_ai_text").empty()) return true;
    Segment segment(0, sizeof(marker) - 1); segment.tags.insert("local_ai");
    segmentation->AddSegment(segment); return false;
  }
};
class AiTranslator : public Translator {
 public:
  explicit AiTranslator(const Ticket& ticket) : Translator(ticket) {}
  an<Translation> Query(const string& input, const Segment& segment) override {
    if (!segment.HasTag("local_ai")) return nullptr;
    auto text = engine_->context()->get_property("_local_ai_text");
    if (text.empty()) return nullptr;
    auto candidate = New<SimpleCandidate>("local_ai", segment.start, segment.end, text,
                                          "AI · Tab/空格确认 · Esc返回");
    candidate->set_preedit("AI 补全预览");
    return New<UniqueTranslation>(candidate);
  }
};
} // namespace local_ai
static void rime_local_ai_initialize() {
  local_ai::worker = std::make_unique<local_ai::Worker>();
  auto& registry = rime::Registry::instance();
  registry.Register("local_ai_processor", new rime::Component<local_ai::AiProcessor>);
  registry.Register("local_ai_segmentor", new rime::Component<local_ai::AiSegmentor>);
  registry.Register("local_ai_translator", new rime::Component<local_ai::AiTranslator>);
}
static void rime_local_ai_finalize() { local_ai::worker.reset(); }
RIME_REGISTER_MODULE(local_ai)
