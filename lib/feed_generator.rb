CommitStruct = Struct.new(:sha, :feed_id, :date, :message,
                          :author_name, :author_email)
class FeedGenerator
  def initialize(user, repo, feed)
    @user = user
    @repo = repo
    @name = "#{@user}/#{@repo}"
    @feed = feed
    @github = Octokit::Client.new
  end

  def make_feed
    base_link = "https://github.com/#{@name}/commit"

    tags = @github.tags("#{@user}/#{@repo}")
    hashes = tags.map {|c| c["commit"]["sha"] }

    commits = @feed.commits.first(20)
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
      resp = @github.commit("#{@user}/#{@repo}", sha).commit
      author = resp["author"]
      date = author[:date]
      CommitStruct.new(sha, @feed.id, date, resp[:message], author[:name], author[:email])
    end
  end
end
