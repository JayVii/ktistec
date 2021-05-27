require "../task"

require "../../framework/constants"
require "../../framework/signature"
require "../activity_pub/activity"
require "../activity_pub/actor"
require "../activity_pub/collection"
require "../activity_pub/object"
require "../relationship/content/inbox"
require "../relationship/content/outbox"
require "../relationship/content/timeline"
require "../relationship/social/follow"

class Task
  class Deliver < Task
    include Ktistec::Constants
    include Ktistec::Open

    belongs_to sender, class_name: ActivityPub::Actor, foreign_key: source_iri, primary_key: iri
    validates(sender) { "missing: #{source_iri}" unless sender? }

    belongs_to activity, class_name: ActivityPub::Activity, foreign_key: subject_iri, primary_key: iri
    validates(activity) { "missing: #{subject_iri}" unless activity? }

    def recipients
      [activity.to, activity.cc, sender.iri].flatten.flat_map do |recipient|
        if recipient == sender.iri
          sender.iri
        elsif recipient && (actor = ActivityPub::Actor.dereference?(recipient))
          actor.iri
        elsif recipient && recipient =~ /^#{sender.iri}\/followers$/
          Relationship::Social::Follow.where(
            to_iri: sender.iri,
            confirmed: true
          ).select(&.actor?).map(&.actor.iri)
        end
      end.compact.sort.uniq
    end

    # if the activity is a delete, the object will already have been
    # deleted so herein and throughout don't validate and save the
    # associated models -- they shouldn't have changed anyway.

    def deliver(to recipients)
      recipients.each do |recipient|
        # the sender special case
        if recipient == sender.iri
          Relationship::Content::Outbox.new(
            owner: sender,
            activity: activity
          ).save(skip_associated: true)
          # handle timeline
          if (object = ActivityPub::Object.dereference?(activity.object_iri))
            if Relationship::Content::Timeline.find?(to_iri: object.iri).nil?
              if activity.is_a?(ActivityPub::Activity::Announce)
                Relationship::Content::Timeline.new(
                  owner: sender,
                  object: object
                ).save(skip_associated: true)
              elsif activity.is_a?(ActivityPub::Activity::Create) && object.in_reply_to_iri.nil?
                Relationship::Content::Timeline.new(
                  owner: sender,
                  object: object
                ).save(skip_associated: true)
              end
            end
          end
          # bail out
          next
        end
        unless (actor = ActivityPub::Actor.dereference?(recipient))
          message = "recipient does not exist: #{recipient}"
          failures << Failure.new(message)
          Log.info { message }
          next
        end
        if actor.local?
          Relationship::Content::Inbox.new(
            owner: actor,
            activity: activity,
          ).save(skip_associated: true)
        elsif (inbox = actor.inbox)
          body = activity.to_json_ld
          headers = Ktistec::Signature.sign(sender, inbox, body)
          response = HTTP::Client.post(inbox, headers, body)
          unless response.success?
            message = "failed to deliver to #{inbox}: [#{response.status_code}] #{response.body}"
            failures << Failure.new(message)
            Log.info { message }
          end
        else
          message = "recipient doesn't have an inbox: #{recipient}"
          failures << Failure.new(message)
          Log.info { message }
        end
      end
    end

    def perform
      deliver to: recipients
    end
  end
end
