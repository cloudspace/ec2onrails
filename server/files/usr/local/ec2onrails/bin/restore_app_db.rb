#!/usr/bin/ruby

#    This file is part of EC2 on Rails.
#    http://rubyforge.org/projects/ec2onrails/
#
#    Copyright 2007 Paul Dowman, http://pauldowman.com/
#
#    EC2 on Rails is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    EC2 on Rails is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

require "rubygems"
require "optiflag"
require "fileutils"
require "#{File.dirname(__FILE__)}/../lib/mysql_helper"
require "#{File.dirname(__FILE__)}/../lib/s3_helper"
require "#{File.dirname(__FILE__)}/../lib/utils"

module CommandLineArgs extend OptiFlagSet
  optional_flag "bucket"
  optional_flag "dir"
  and_process!
end

bucket = ARGV.flags.bucket
dir = ARGV.flags.dir || "database"
@s3 = Ec2onrails::S3Helper.new(bucket, dir)
@mysql = Ec2onrails::MysqlHelper.new
@temp_dir = "/mnt/tmp/ec2onrails-backup-#{@s3.bucket}-#{dir.gsub(/\//, "-")}"
if File.exists?(@temp_dir)
  puts "Temp dir exists (#{@temp_dir}), aborting. Is another backup process running?"
  exit
end

begin
  FileUtils.mkdir_p @temp_dir
  
  file = "#{@temp_dir}/dump.sql.gz"
  @s3.retrieve_file(file)
  @mysql.load_from_dump(file)
  
  @s3.retrieve_files("mysql-bin.", @temp_dir)
  logs = Dir.glob("#{@temp_dir}/mysql-bin.[0-9]*").sort
  logs.each {|log| @mysql.execute_binary_log(log) }
  
  @mysql.execute_sql "reset master" # TODO  maybe we shouldn't do this if we're not going to delete the logs from the S3 bucket because this restarts the numbering again
ensure
  FileUtils.rm_rf(@temp_dir)
end
