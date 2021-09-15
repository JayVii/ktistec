require "../framework/**"
require "../models/**"
require "../controllers/**"
require "../handlers/**"
require "../workers/**"

Ktistec::Server.run do
  Log.setup_from_env
  spawn do
    Session.clean_up_stale_sessions
    TaskWorker.start do
      Task::UpdateMetrics.schedule_unless_exists
    end
  end
end
