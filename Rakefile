require 'fileutils'

desc "Reset"
task :reset do
  files  = ['musync.sqlite3']
  files += Dir['tmp/files/*']
  files += Dir['tmp/staging/*']
  files += Dir['songs/*']
  FileUtils.rm_rf(files, :verbose => true)
end
