require "../framework/controller"
require "../framework/topic"

require "../models/relationship/content/follow/hashtag"
require "../models/task/fetch/hashtag"

class StreamsController
  include Ktistec::Controller

  macro stop
    raise Ktistec::Topic::Stop.new
  end

  ## Turbo Stream Action helpers

  # Renders action to replace the actor icon.
  #
  def self.replace_actor_icon(io, id)
    actor = ActivityPub::Actor.find(id)
    # omit "data-actor-id" so that replacement can only be attempted once
    body = %Q|<img src="#{actor.icon}">|
    stream_replace(io, selector: ":is(i,img)[data-actor-id='#{actor.id}']", body: body)
  end

  # Renders action to replace the refresh posts message.
  #
  def self.replace_refresh_posts_message(io, path = "")
    body = render "src/views/partials/refresh-posts.html.slang"
    stream_replace(io, id: "refresh-posts-message", body: body)
  end

  # Limits the number of long-lived connections.
  #
  # Limits the number of long-lived connections by maintaining a pool
  # of connections. When the pool is full, adding a new connection
  # closes the oldest connection.
  #
  # A "connection" is any subclass of `IO`.
  #
  class ConnectionPool
    def initialize(capacity)
      @connections = Array(IO?).new(capacity, nil)
      @index = 0
    end

    # Returns the capacity of the pool.
    #
    def capacity
      @connections.size
    end

    # Returns the number of connections in the pool.
    #
    def size
      @connections.count(&.nil?.!)
    end

    # Pushes `connection` into the pool.
    #
    # If the pool is at capacity, the oldest connection is closed,
    # removed from the pool, and returned.
    #
    def push(connection)
      index = @index % @connections.size
      last, @connections[index] = @connections[index], connection
      @index += 1
      last.close unless last.nil? || last.closed?
      last
    end

    # Returns `true` if the pool includes `connection`.
    #
    def includes?(connection)
      @connections.includes?(connection)
    end
  end

  # ensure there are no more than five long-lived connections handling
  # subscriptions "per browser", which is here implemented as "per
  # session". this helps limit blocking and ensures that ktistec never
  # runs out of file descriptors/sockets (we hit 1024 simultaneous
  # connections once, while testing at epiktistes.com -- poor thing
  # couldn't even connect to the database).

  @@pools = Hash(Session, ConnectionPool).new { |h, k| h[k] = ConnectionPool.new(5) }

  get "/stream/tags/:hashtag" do |env|
    hashtag = env.params.url["hashtag"]
    if (first_count = Tag::Hashtag.all_objects_count(hashtag)) < 1
      not_found
    end
    Ktistec::Topic{"/actor/refresh", hashtag_path(hashtag)}.tap do |topic|
      setup_response(env.response, topic.object_id)
      topic.subscribe do |subject, value|
        case subject
        when "/actor/refresh"
          if value && (id = value.to_i64?)
            replace_actor_icon(env.response, id)
          end
        else
          task = Task::Fetch::Hashtag.find(source: env.account.actor, name: hashtag)
          follow = Relationship::Content::Follow::Hashtag.find(actor: env.account.actor, name: hashtag)
          count = Tag::Hashtag.all_objects_count(hashtag)
          body = tag_page_tag_controls(env, hashtag, task, follow, count)
          stream_replace(env.response, id: "tag_page_tag_controls", body: body)
          if count > first_count
            first_count = count
            replace_refresh_posts_message(env.response)
          end
        end
      rescue HTTP::Server::ClientError
        stop
      end
    end
  end

  get "/stream/objects/:id/thread" do |env|
    id = env.params.url["id"].to_i
    unless (object = ActivityPub::Object.find?(id))
      not_found
    end
    thread = object.thread(for_actor: env.account.actor)
    first_count = thread.size
    Ktistec::Topic{"/actor/refresh", thread.first.thread.not_nil!}.tap do |topic|
      setup_response(env.response, topic.object_id)
      topic.subscribe do |subject, value|
        case subject
        when "/actor/refresh"
          if value && (id = value.to_i64?)
            replace_actor_icon(env.response, id)
          end
        else
          thread = object.thread(for_actor: env.account.actor)
          count = thread.size
          task = Task::Fetch::Thread.find?(source: env.account.actor, thread: thread.first.thread)
          follow = Relationship::Content::Follow::Thread.find?(actor: env.account.actor, thread: thread.first.thread)
          body = thread_page_thread_controls(env, thread, task, follow)
          stream_replace(env.response, id: "thread_page_thread_controls", body: body)
          if count > first_count
            first_count = count
            replace_refresh_posts_message(env.response)
          end
        end
      rescue HTTP::Server::ClientError
        stop
      end
    end
  end

  get "/stream/actor/timeline" do |env|
    since = Time.utc
    first_count = timeline_count(env, since)
    Ktistec::Topic{"/actor/refresh", "#{actor_path(env.account.actor)}/timeline"}.tap do |topic|
      setup_response(env.response, topic.object_id)
      topic.subscribe do |subject, value|
        case subject
        when "/actor/refresh"
          if value && (id = value.to_i64?)
            replace_actor_icon(env.response, id)
          end
        else
          count = timeline_count(env, since)
          if count > first_count
            first_count = count
            replace_refresh_posts_message(env.response)
          else
            stream_no_op(env.response)
          end
        end
      rescue HTTP::Server::ClientError
        stop
      end
    end
  end

  private def self.timeline_count(env, since)
    filters = env.params.query.fetch_all("filters")
    actor = env.account.actor
    if filters.includes?("no-shares") && filters.includes?("no-replies")
      timeline = actor.timeline(since: since, inclusion: [Relationship::Content::Timeline::Create], exclude_replies: true)
    elsif filters.includes?("no-shares")
      timeline = actor.timeline(since: since, inclusion: [Relationship::Content::Timeline::Create])
    elsif filters.includes?("no-replies")
      timeline = actor.timeline(since: since, exclude_replies: true)
    else
      timeline = actor.timeline(since: since)
    end
  end

  get "/stream/everything" do |env|
    Ktistec::Topic{"/actor/refresh", everything_path}.tap do |topic|
      setup_response(env.response, topic.object_id)
      topic.subscribe do |subject, value|
        case subject
        when "/actor/refresh"
          if value && (id = value.to_i64?)
            replace_actor_icon(env.response, id)
          end
        else
          stream_refresh(env.response)
        end
      rescue HTTP::Server::ClientError
        stop
      end
    end
  end

  def self.setup_response(response : HTTP::Server::Response, topic_id)
    response.content_type = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["X-Topic-Id"] = topic_id.to_s
    # call `upgrade` to write the headers to the output
    response.upgrade {}
    response.flush
  end

  # Sends a no-op action.
  #
  def self.stream_no_op(io)
    stream_action(io, nil, "no-op", nil, nil)
  end

  {% for action in %w(append prepend replace update remove before after morph refresh) %}
    def self.stream_{{action.id}}(io, body = nil, id = nil, selector = nil)
      stream_action(io, body, {{action}}, id, selector)
    end
  {% end %}

  def self.stream_action(io : IO, body : String?, action : String, id : String?, selector : String?)
    if id && !selector
      io.puts %Q|data: <turbo-stream action="#{action}" target="#{id}">|
    elsif selector && !id
      io.puts %Q|data: <turbo-stream action="#{action}" targets="#{selector}">|
    else
      io.puts %Q|data: <turbo-stream action="#{action}">|
    end
    if body
      io.puts "data: <template>"
      body.each_line do |line|
        io.puts "data: #{line}"
      end
      io.puts "data: </template>"
    end
    io.puts "data: </turbo-stream>"
    io.puts
    io.flush
  end
end

module ActivityPub
  class Object
    def after_create
      Ktistec::Topic{Ktistec::ViewHelper.everything_path}.notify_subscribers
    end

    # updates the `subject` based on the `thread` when an object is
    # saved.

    def after_save
      previous_def
      Ktistec::Topic.rename_subject(self.iri, self.thread)
    end
  end
end
