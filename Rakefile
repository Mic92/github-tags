namespace :db do
  require 'rubygems'
  require 'sequel'
  Sequel.extension :migration

  task :migrate do
    m = Sequel::Migrator
    db = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://library.sqlite')
    dir = "migrations"

    target = ENV['TARGET'] ? ENV['TARGET'].to_i : nil
    current = ENV['CURRENT'] ? ENV['CURRENT'].to_i : nil

    m.run(db, dir, :target => target, :current => current)
  end
end
