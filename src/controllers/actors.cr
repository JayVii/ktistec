require "../framework/controller"
require "../views/view_helper"
require "../models/activity_pub/activity/follow"
require "../models/task/refresh_actor"

class ActorsController
  include Ktistec::Controller
  include Ktistec::ViewHelper

  skip_auth ["/actors/:username"]

  get "/actors/:username" do |env|
    username = env.params.url["username"]

    actor = Account.find(username: username).actor

    ok "actors/actor"
  rescue Ktistec::Model::NotFound
    not_found
  end

  get "/actors/:username/timeline" do |env|
    username = env.params.url["username"]

    unless (account = Account.find?(username: username))
      not_found
    end
    unless account == env.account
      forbidden
    end

    actor = account.actor

    objects = actor.timeline(*pagination_params(env))

    ok "actors/timeline"
  end

  get "/actors/:username/notifications" do |env|
    username = env.params.url["username"]

    unless (account = Account.find?(username: username))
      not_found
    end
    unless account == env.account
      forbidden
    end

    actor = account.actor

    activities = actor.notifications(*pagination_params(env))

    ok "actors/notifications"
  end

  get "/remote/actors/:id" do |env|
    id = env.params.url["id"].to_i

    actor = ActivityPub::Actor.find(id)

    ok "actors/remote"
  rescue Ktistec::Model::NotFound
    not_found
  end

  post "/remote/actors/:id/refresh" do |env|
    id = env.params.url["id"].to_i

    actor = ActivityPub::Actor.find(id)

    unless Task::RefreshActor.exists?(actor.iri)
      Task::RefreshActor.new(source: env.account.actor, actor: actor).schedule
    end

    ok
  rescue Ktistec::Model::NotFound
    not_found
  end
end
