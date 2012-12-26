require "bundler/setup"
require "rss"

require "sinatra"
require "dalli"
require "slim"

require "github_api"

CLIENT_ID = ENV["GITHUB_CLIENT_ID"]
CLIENT_SECRET = ENV["GITHUB_CLIENT_SECRET"]

set :cache, Dalli::Client.new(ENV["MEMCACHE_SERVERS"],
                              username: ENV["MEMCACHE_USERNAME"],
                              password: ENV["MEMCACHE_PASSWORD"])

set :github, Github.new(client_id: CLIENT_ID, client_secret: CLIENT_SECRET)

Commit = Struct.new(:author_name, :author_email, :date, :message)

helpers do
  def has_errors(field)
    if @errors and @errors[field]
      "has-errors"
    else
      ""
    end
  end
end

def generate_feed(user, repo, limit)
  base_link = "https://github.com/#{user}/#{repo}/commit"
  tags = settings.github.repos.tags(user, repo)[0..limit]

  rss = RSS::Maker.make("atom") do |maker|
    maker.channel.author = user
    maker.channel.updated = Time.now.to_s
    maker.channel.about = "https://github.com/#{user}/#{repo}"
    maker.channel.title = "Git Tags of #{user}/#{repo}"

    tags.each do |tag|
      sha = tag["commit"]["sha"][0..15]
      commit = settings.cache.get(sha)
      if commit.nil?
        resp = settings.github.repos.commits.get(user, repo, sha)["commit"]
        author = resp["author"]
        date = Time.parse(author[:date])
        commit = Commit.new(author[:name], author[:email],
                            date, resp[:message])
        settings.cache.set(sha, commit)
      end
      maker.items.new_item do |item|
        item.title = "#{user}/#{repo} published #{tag["name"]}"
        item.author = "#{commit.author_name} <#{commit.author_email}>"
        item.link = "#{base_link}/#{sha}"
        item.updated = commit.date
        item.description = "by #{commit.author_name} at #{commit.date}:\n #{commit.message}"
      end
    end
  end

  return rss.to_s
end

get "/feed/:user/:repo\.atom" do
  content_type 'application/atom+xml'

  limit = params[:limit] || 5
  limit = limit.to_i
  unless (1..20).include?(limit)
    limit = 5
  end

  user = params[:user]
  repo = params[:repo]

  key = "#{user}-#{repo}-#{limit}"
  cache = settings.cache.get(key)
  unless cache.nil?
    time = 10 * 60
    response['Cache-Control'] = "public, max-age=#{time}"
    return cache
  end

  begin
    rss = generate_feed(user, repo, limit).to_s
    time = 10 * 60
    response['Cache-Control'] = "public, max-age=#{time}"
    settings.cache.set(key, rss, time)

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
  limit = params[:limit]
  if limit.nil? or limit.empty?
    @errors[:limit] = "please set a feed limit"
  end
  limit = limit.to_i
  if not (1..20).include?(limit)
    @errors[:limit] = "feed limit must between 1 and 20"
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
    @feed_link += "?limit=#{limit}" if limit != 5
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
      label Entries per Feed:
      select class=has_errors(:limit) name="limit"
        option value="5" 5
        option value="1" 1
        option value="10" 10
        option value="15" 15
        option value="20" 20
      br
      input type="submit" value="Get the Feed"
  - if @feed_link
    p Put this feed link in your reader
    p
    a href=url(@feed_link) = url(@feed_link)
