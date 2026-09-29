#include <rime_api.h>
#include <chrono>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

void Require(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
std::string Status(RimeApi* api, RimeSessionId session) {
  char out[128] = {}; api->get_property(session, "local_ai_status", out, sizeof(out)); return out;
}
std::string Candidate(RimeApi* api, RimeSessionId session) {
  RIME_STRUCT(RimeContext, context);
  if (!api->get_context(session, &context)) return "";
  std::string text;
  if (context.menu.num_candidates) text = context.menu.candidates[0].text;
  api->free_context(&context); return text;
}
void Trigger(RimeApi* api, RimeSessionId session) {
  auto start = std::chrono::steady_clock::now();
  Require(api->process_key(session, 0xff09, 4), "trigger must be consumed");
  auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count();
  Require(ms < 150, "inference blocked key processing");
}
std::string Wait(RimeApi* api, RimeSessionId session) {
  for (int i=0; i<120; ++i) {
    std::this_thread::sleep_for(std::chrono::milliseconds(50)); Trigger(api,session);
    auto status = Status(api,session); if (status != "pending") return status;
  }
  throw std::runtime_error("completion timeout");
}
int wmain(int argc, wchar_t** wide_argv) {
  std::string args[4];
  const char* argv[4] = {};
  for (int i = 0; i < argc && i < 4; ++i) {
    args[i] = std::filesystem::path(wide_argv[i]).u8string();
    argv[i] = args[i].c_str();
  }
  if (argc != 4) { std::cerr << "usage: local_ai_probe shared-data user-data success|error|cancel|destroy\n"; return 2; }
  auto* api = rime_get_api();
  std::filesystem::create_directories(std::filesystem::u8path(argv[2]));
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir=argv[1]; traits.user_data_dir=argv[2]; traits.app_name="rime.local_ai_probe";
  traits.log_dir=argv[2];
  api->setup(&traits); api->initialize(&traits);
  if (api->start_maintenance(true)) api->join_maintenance_thread();
  auto session=api->create_session(); int rc=0;
  try {
    Require(api->select_schema(session,"local_ai_pinyin"),"cannot select AI schema");
    Require(api->simulate_key_sequence(session,"nihao"),"normal pinyin failed");
    const auto original=Candidate(api,session); Require(!original.empty(),"no normal pinyin candidate");
    Trigger(api,session); Require(Status(api,session)=="pending","request not started");
    RIME_STRUCT(RimeCommit, early); Require(!api->get_commit(session,&early),"request committed text prematurely");
    const std::string mode=argv[3];
    if (mode=="destroy") {
      const auto start=std::chrono::steady_clock::now(); api->destroy_session(session); session=0;
      const auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count();
      Require(ms<150,"session destruction blocked on model");
      std::this_thread::sleep_for(std::chrono::milliseconds(600));
    } else if (mode=="cancel") {
      api->process_key(session,'z',0);
      std::this_thread::sleep_for(std::chrono::milliseconds(600));
      Trigger(api,session);
      Require(Status(api,session)=="pending","stale completion was displayed after input changed");
      api->process_key(session,0xff1b,0);
      Require(Candidate(api,session).empty(),"escape did not clear normal composition");
    } else if (mode=="error") {
      Require(Wait(api,session)=="unavailable","backend failure not handled");
      Require(Candidate(api,session)==original,"backend failure changed normal candidates");
      Require(api->commit_composition(session),"normal input unavailable after backend failure");
    } else {
      Require(Wait(api,session)=="preview","preview not displayed");
      auto completion=Candidate(api,session);
      Require(completion.size()>original.size(),"completion is empty");
      Require(completion.find("[MOCK]")!=std::string::npos,"mock marker missing");
      api->process_key(session,0xff1b,0);
      Require(Candidate(api,session)==original,"escape did not restore original composition");
      Trigger(api,session); Require(Wait(api,session)=="preview","second completion failed");
      completion=Candidate(api,session);
      api->process_key(session,0xff09,0);
      RIME_STRUCT(RimeCommit, commit); Require(api->get_commit(session,&commit),"accept did not commit");
      const std::string committed=commit.text; api->free_commit(&commit);
      Require(committed==completion,"committed text differs from preview");
      std::cout << "accepted_utf8=" << committed << '\n';
    }
    std::cout << "PASS " << mode << " (real Rime session; mock backend)\n";
  } catch (const std::exception& e) { std::cerr << "FAIL: " << e.what() << '\n'; rc=1; }
  if (session) api->destroy_session(session); api->finalize(); return rc;
}
