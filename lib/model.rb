db = Sequel.connect(ENV["DATABASE_URL"] || "sqlite://tagfeeds.db")
db.loggers << Logger.new(STDOUT)

class Feed < Sequel::Model
  one_to_many :commits
end
Feed.plugin :association_dependencies, commits: :delete
class Commit < Sequel::Model
  many_to_one :feed
end
