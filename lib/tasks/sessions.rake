namespace :sessions do
  desc "End active sessions that have been inactive for thirty days"
  task cleanup_stale: :environment do
    puts "Ended #{Sessions::CleanupStale.call} stale sessions"
  end
end
