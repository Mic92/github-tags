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

set :db, Sequel.connect(ENV['DATABASE_URL'] || 'postgres://localhost/gittags')
settings.db.loggers << Logger.new(STDOUT)

class Feed < Sequel::Model
  one_to_many :commits
end
class Commit < Sequel::Model
  many_to_one :feed
end

set :github, Github.new(client_id: CLIENT_ID, client_secret: CLIENT_SECRET)

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
    tag_names = Hash[tags.map {|t| [t["commit"]["sha"], t["name"]]}]

    commits = @feed.commits
    cached_hashes = commits.map {|c| c.sha }

    new_commits = get_commits(hashes - cached_hashes)
    commits << Commit.multi_insert(new_commits) if new_commits.size > 0

    commits.sort!{|a,b| b.date <=> a.date}

    rss = RSS::Maker.make("atom") do |maker|
      maker.channel.author = @user
      maker.channel.updated = Time.now.to_s
      maker.channel.about = "https://github.com/#{@name}"
      maker.channel.title = "Git Tags of #{@name}"

      commits.each do |commit|
        maker.items.new_item do |item|
          item.title = "#{@name} published #{tag_names[commit.sha]}"
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
      { sha: sha, feed_id: @feed.id, date: date, message: resp[:message],
        author_name: author[:name], author_email: author[:email] }
    end
  end
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

__END__
@@layout
doctype html
html
  head
    meta charset="utf-8"
    title Github Tag Feeds
    link rel="stylesheet" media="screen, projection" href="/styles.css"
    link rel="stylesheet" href="gh-fork-ribbon.css"
    /[if IE]
      link rel="stylesheet" href="gh-fork-ribbon.ie.css"
    meta name="viewport" content="width=device-width, initial-scale=1"
    /[if lt IE 9]
      script src="http://html5shiv.googlecode.com/svn/trunk/html5.js"
  body
    .github-fork-ribbon-wrapper.right
      .github-fork-ribbon
        a href="https://github.com/simonwhitaker/github-fork-ribbon-css" Fork me on GitHub

    == yield
@@index

#content
  h1 Github Tag Feeds
  h2 subscribe to git tags of github projects
  - if @errors
    p
      span.error-box Your form contains errors:
      ul
      - for error in @errors
        li
          = error.last
  p
    form action="/" method="POST"
      span.github-url
        ' github.com/
        input class=has_errors(:user) type="text" name="user" value="" placeholder="Github user"
        '/
        input class=has_errors(:repo) type="text" name="repo" value="" placeholder="Github repository"
      br
      input type="submit" value="Get the Feed"
  - if @feed_link
    p Put this feed link in your reader
    p
    a href=url(@feed_link) = url(@feed_link)
