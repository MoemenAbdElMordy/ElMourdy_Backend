namespace :curriculum do
  desc "Idempotently create the folder-tree presentation for legacy curriculum"
  task backfill_folders: :environment do
    Branch.find_each do |branch|
      Curriculum::BackfillFolderTree.call(branch:)
      puts "Backfilled branch #{branch.id}: #{CurriculumNode.where(branch:).count} nodes"
    end
  end
end
