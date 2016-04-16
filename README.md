github-tags
===========

github-tags is a sinatra app to generate an rss feed with the latest git tags of
a github project.

[Demo](http://githubtags.higgsboson.tk/)

How to set up it on heroku
==========================

Get an [heroku account](https://api.heroku.com/signup)
and follow the [starting
guide](https://devcenter.heroku.com/articles/quickstart) to create an new
application

Clone the source code of your new application:

    $ git clone git@heroku.com:YOUR-APP-NAME.git

Add this project as a remote

    $ git remote add origin git@github.com:Mic92/github-tags.git
    $ git pull origin master
    $ git push heroku

Configure Postgres

    $ heroku addons:create heroku-postgresql:hobby-dev
    Adding heroku-postgresql:dev to sushi... done, v69 (free)
    Attached as HEROKU_POSTGRESQL_RED
    Database has been created and is available

NOTE: HEROKU\_POSTGRESQL\_RED can differ in your case

    $ heroku pg:promote HEROKU_POSTGRESQL_RED_URL

Optionally:
-----------

To increase your api request limit per hour, you can register the
site as a github app: https://github.com/settings/applications/new

Then export the client id and client secret of your github app to the enviroment variables of heroku:

    $ heroku config:add GITHUB_CLIENT_ID=_YOUR_CLIENT_ID_
    $ heroku config:add GITHUB_CLIENT_SECRET=_YOUR_CLIENT_SECRET_

Check your setup by visiting https://your-heroku-app.herokuapps.com/status (replace your your-heroku-app with your application name)
If Github Client Key and Github Client Secret is present, you can hit the "Get an OAuth key"-link.
After login export the OAuth token to heroku:

    $ heroku config:add GITHUB_OAUTH_TOKEN=_YOUR_OAUTH_TOKEN_

Now you can recheck your setup by visiting https://your-heroku-app.herokuapps.com/status again
