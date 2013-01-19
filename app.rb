require "bundler/setup"
require "rss"

require "sinatra"
require "sequel"
require "uri"
require "slim"
require "logger"

require "pry"

require "github_api"

require "./feed_generator"

CLIENT_ID = ENV["GITHUB_CLIENT_ID"]
CLIENT_SECRET = ENV["GITHUB_CLIENT_SECRET"]
OAUTH_TOKEN = ENV["GITHUB_OAUTH_TOKEN"]

set :db, Sequel.connect(ENV["DATABASE_URL"] || "sqlite://tagfeeds.db")
settings.db.loggers << Logger.new(STDOUT)

class Feed < Sequel::Model
  one_to_many :commits
end
class Commit < Sequel::Model
  many_to_one :feed
end


set :github, Github.new(client_id: CLIENT_ID,
                        client_secret: CLIENT_SECRET,
                        oauth_token: OAUTH_TOKEN)

helpers do
  def has_errors(field)
    if @errors and @errors[field]
      "has-errors"
    else
      ""
    end
  end
end

get "/register" do
  address = settings.github.authorize_url redirect_uri: url("/callback")
  redirect address
end

get "/callback" do
  authorization_code = params[:code]
  token = settings.github.get_token authorization_code
  @access_token = token.token
  slim :callback
end

get "/status" do
  slim :status
end

# legacy links
get "/feed/:user/:repo\.atom" do
  redirect "/github/#{params[:user]}/#{params[:repo]}.atom", 301
end

get "/github/:user/:repo\.atom" do
  content_type 'application/atom+xml'

  user = params[:user]
  repo = params[:repo]

  feed = Feed.find_or_create(name: "#{user}/#{repo}")

  left_time = 10 * 60 - (Time.now - (feed.updated_at or Time.at(0)))
  if feed.content and left_time > 0
    response['Cache-Control'] = "public, max-age=#{left_time}"
    return feed.content
  end

  begin
    generator = FeedGenerator.new(user, repo, feed)
    rss = generator.make_feed
    response['Cache-Control'] = "public, max-age=#{10 * 60}"
    feed.content = rss
    feed.updated_at = Time.now
    feed.save

    return rss
  rescue Exception => e
    puts e.inspect
    puts e.backtrace

    rss = RSS::Maker.make("atom") do |maker|
      maker.channel.author = user
      maker.channel.updated = Time.now.to_s
      maker.channel.about = "http://gittags.higgsboson.tk/"
      maker.channel.title = "Github Tags Feed"
      maker.items.new_item do |item|
        item.id = "error"
        item.title = "Error while generating feed:"
        item.updated = Time.now.to_s
        item.description = e.message
      end
    end

    return rss
  end
end

post "/" do
  @errors = {}

  user = params[:user]
  if user.nil? or user.empty?
    @errors[:user] = "please fill in a github user"
  end
  repo = params[:repo]
  if repo.nil? or repo.empty?
    @errors[:repo] = "please fill in a github repository"
  end

  begin
    settings.github.users.get user: user
    begin
      settings.github.repos.get user, repo
    rescue Github::Error::NotFound => e
      @errors[:repo] = "git repository does not exist"
    end
  rescue Github::Error::NotFound => e
    @errors[:user] = "github user does not exist"
  end

  if @errors.size == 0
    @feed_link = "/github/#{user}/#{repo}.atom"
    @errors = nil
  end
  return slim :index
end

get "/" do
  slim :index
end
