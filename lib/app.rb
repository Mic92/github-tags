module GithubTags
  class App < Sinatra::Base
    def has_errors(field)
      if @errors and @errors[field]
        "has-errors"
      else
        ""
      end
    end

    Octokit.configure do |c|
      c.client_id = ENV['GITHUB_CLIENT_ID']
      c.client_secret = ENV['GITHUB_CLIENT_SECRET']
      c.access_token = ENV['GITHUB_OAUTH_TOKEN']
    end

    set :github, Octokit::Client.new

    get "/register" do
      address = settings.github.authorize_url(
        ENV['GITHUB_CLIENT_ID'],
        redirect_uri: url("/callback")
      )
      redirect address
    end

    get "/callback" do
      authorization_code = params[:code]
      token = settings.github.exchange_code_for_token authorization_code
      @access_token = token.access_token
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
        settings.github.user user
        begin
          settings.github.repository "#{user}/#{repo}"
        rescue Octokit::NotFound => e
          @errors[:repo] = "github repository does not exist"
        end
      rescue Octokit::NotFound
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
  end
end
