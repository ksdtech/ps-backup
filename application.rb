#!/usr/bin/env ruby

require 'rubygems'
require 'net/sftp'

# app_config.rb holds private information
require 'app_config'

APP_ROOT   = Dir.pwd
LOCAL_DIR  = APP_CONFIG['local_dir']
REMOTE_DIR = APP_CONFIG['remote_dir']

# Setup
FileUtils.mkdir_p(LOCAL_DIR) rescue false

def remote_dir_entries(dir, sftp)
  handle = sftp.opendir!(dir)
  entries = sftp.readdir!(handle).collect { |e| e.name }.delete_if { |n| ['.', '..'].include? n }.sort
end

def remove_remote_dir_contents(dir, sftp)
  handle = sftp.opendir!(dir)
  sftp.readdir!(handle).each do |entry|
    next if ['.', '..'].include? entry.name
    path = "#{dir}/#{entry.name}"
    if entry.directory?
      # recurse
      remove_remote_dir(path, sftp)
    else
      puts "removing file #{path}"
      sftp.remove!(path)
    end
  end
end

def remove_remote_dir(dir, sftp)
  puts "removing contents of #{dir}"
  remove_remote_dir_contents(dir, sftp)
  puts "removing dir #{dir}"
  sftp.rmdir!(dir)
end

def local_dir_entries(dir)
  Dir.entries(dir).delete_if { |n| ['.', '..'].include? n }.sort
end

def download_files
  Net::SFTP.start(APP_CONFIG['sftp_server'], APP_CONFIG['sftp_username'], :password => APP_CONFIG['sftp_password']) do |sftp|
    puts "finding latest backup set"
    entries = remote_dir_entries(REMOTE_DIR, sftp)
    if entries.empty?
      puts "no backup sets to download"
    else
      dir = entries.last
      puts "downloading last backup set #{dir}"
      begin
        sftp.download!("#{REMOTE_DIR}/#{dir}", "#{LOCAL_DIR}/#{dir}", :recursive => true) do |event, downloader, *args|
          case event
          when :open then
            # args[0] : file metadata
            puts " #{args[0].remote} -> #{args[0].local} (#{args[0].size} bytes}"
          when :close then
            # args[0] : file metadata
            puts " finished with #{args[0].remote}"
          when :finish then
            puts " all done!"
          end
        end
      rescue 
        puts "failed"
      end
    end
  end
end

def cleanup_files
  puts "removing local files"
  entries = local_dir_entries(LOCAL_DIR)
  if entries.size > 5
    entries[0, entries.size-5].each do |dir|
      puts "removing local #{dir}"
      # FileUtils.rm_r("#{LOCAL_DIR}/#{dir}", :secure => true, :force => true)
    end
  else
    puts "only #{entries.size} backup sets in local"
  end
  
  puts "removing remote files"
  entries = []
  Net::SFTP.start(APP_CONFIG['sftp_server'], APP_CONFIG['sftp_username'], :password => APP_CONFIG['sftp_password']) do |sftp|
    entries = remote_dir_entries(REMOTE_DIR, sftp)
    if entries.size > 30
      entries[0, entries.size - 30].each do |dir|
        puts "removing remote #{dir}"
        remove_remote_dir("#{REMOTE_DIR}/#{dir}", sftp)
      end
    else
      puts "only #{entries.size} backup sets in remote"
    end
  end
end


# do the work
download_files
cleanup_files

