require "bundler/setup"
require "rss"

require "sinatra"
require "sequel"
require "uri"
require "slim"
require "logger"

require "pry"

require "github_api"

CLIENT_ID = ENV["GITHUB_CLIENT_ID"]
CLIENT_SECRET = ENV["GITHUB_CLIENT_SECRET"]
OAUTH_TOKEN = ENV["GITHUB_OAUTH_TOKEN"]

set :db, Sequel.connect(ENV['DATABASE_URL'] || 'postgres://localhost/gittags')
settings.db.loggers << Logger.new(STDOUT)

class Feed < Sequel::Model
  one_to_many :commits
end
class Commit < Sequel::Model
  many_to_one :feed
end

CommitStruct = Struct.new(:sha, :feed_id, :date, :message, :author_name, :author_email)

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

class FeedGenerator
  def initialize(user, repo, feed)
    @user = user
    @repo = repo
    @name = "#{@user}/#{@repo}"
    @feed = feed
  end
  def make_feed
    base_link = "https://github.com/#{@name}/commit"

    tags = settings.github.repos.tags(@user, @repo)
    hashes = tags.map {|c| c["commit"]["sha"] }

    commits = @feed.commits
    cached_hashes = commits.map {|c| c.sha }

    new_commits = get_commits((hashes - cached_hashes).uniq)
    if new_commits.size > 0
      inserts = new_commits.map do |c|
        { sha: c.sha, feed_id: c.feed_id, date: c.date, message: c.message,
          author_name: c.author_name, author_email: c.author_email }
      end
      Commit.multi_insert(inserts)
      commits |= new_commits
    end

    commits_by_sha = Hash[commits.map {|c| [c.sha, c]}]

    tags.sort! do |a,b|
      a_date = commits_by_sha[a["commit"]["sha"]].date
      b_date = commits_by_sha[b["commit"]["sha"]].date
      b_date <=> a_date
    end

    rss = RSS::Maker.make("atom") do |maker|
      maker.channel.author = @user
      maker.channel.updated = Time.now.to_s
      maker.channel.about = "https://github.com/#{@name}"
      maker.channel.title = "Git Tags of #{@name}"

      tags.each do |tag|
        commit = commits_by_sha[tag["commit"]["sha"]]
        maker.items.new_item do |item|
          item.title = "#{@name} published #{tag["name"]}"
          item.author = "#{commit.author_name} <#{commit.author_email}>"
          item.link = "#{base_link}/#{commit.sha}"
          item.updated = commit.date
          item.description = "by #{commit.author_name} at #{commit.date}:\n #{commit.message}"
        end
      end
    end

    return rss.to_s
  end

  private
  def get_commits(commits)
    commits.map do |sha|
      resp = settings.github.repos.commits.get(@user, @repo, sha)["commit"]
      author = resp["author"]
      date = Time.parse(author[:date])
      CommitStruct.new(sha, @feed.id, date, resp[:message], author[:name], author[:email])
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

get "/feed/:user/:repo\.atom" do
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
    @feed_link = "/feed/#{user}/#{repo}.atom"
    @errors = nil
  end
  return slim :index
end

get "/" do
  slim :index
end
