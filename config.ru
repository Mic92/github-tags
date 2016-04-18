require 'bundler'
Bundler.require
require "sinatra/base"
require 'json'
require "octokit"
require "logger"
require "rss"
require "sequel"
require "sequel/plugins/association_dependencies.rb"
require "slim"
require "pry"
require "uri"

Dir['./lib/**/*.rb'].each do |file|
  require file
end

use Rack::Static, urls: ["/css", "/js"], root: "public"

run GithubTags::App
