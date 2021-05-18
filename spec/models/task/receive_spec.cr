require "../../../src/models/task/receive"

require "../../spec_helper/model"
require "../../spec_helper/network"
require "../../spec_helper/register"

Spectator.describe Task::Receive do
  setup_spec

  let(receiver) do
    register(with_keys: true).actor
  end
  let(activity) do
    ActivityPub::Activity.new(iri: "https://test.test/activities/activity")
  end

  context "validation" do
    let!(options) do
      {source_iri: receiver.save.iri, subject_iri: activity.save.iri}
    end

    it "rejects missing receiver" do
      new_relationship = described_class.new(**options.merge({source_iri: "missing"}))
      expect(new_relationship.valid?).to be_false
      expect(new_relationship.errors.keys).to contain("receiver")
    end

    it "rejects missing activity" do
      new_relationship = described_class.new(**options.merge({subject_iri: "missing"}))
      expect(new_relationship.valid?).to be_false
      expect(new_relationship.errors.keys).to contain("activity")
    end

    it "successfully validates instance" do
      new_relationship = described_class.new(**options)
      expect(new_relationship.valid?).to be_true
    end
  end

  describe "#deliver_to" do
    subject do
      described_class.new(
        receiver: receiver,
        activity: activity,
        state: %Q|{"deliver_to":[]}|
      )
    end

    it "returns an array of strings" do
      expect(subject.deliver_to).to be_a(Array(String))
    end

    it "returns an empty array" do
      expect(subject.deliver_to).to be_empty
    end
  end

  describe "#deliver_to=" do
    subject { described_class.new }

    it "updates state" do
      expect{subject.deliver_to = ["https://recipient"]}.to change{subject.state}
    end
  end

  let(local_recipient) do
    username = random_string
    ActivityPub::Actor.new(
      iri: "https://test.test/actors/#{username}",
      inbox: "https://test.test/actors/#{username}/inbox"
    )
  end

  let(remote_recipient) do
    username = random_string
    ActivityPub::Actor.new(
      iri: "https://remote/actors/#{username}",
      inbox: "https://remote/actors/#{username}/inbox"
    )
  end

  let(local_collection) do
    ActivityPub::Collection.new(
      iri: "https://test.test/actors/#{random_string}/followers"
    )
  end

  let(remote_collection) do
    ActivityPub::Collection.new(
      iri: "https://remote/actors/#{random_string}/followers"
    )
  end

  describe "#recipients" do
    subject do
      described_class.new(
        receiver: receiver,
        activity: activity
      )
    end

    it "does not include the receiver by default" do
      expect(subject.recipients).not_to contain(receiver.iri)
    end

    context "addressed to the receiver" do
      let(recipient) { receiver }

      before_each { activity.to = [recipient.iri] }

      it "includes the receiver" do
        expect(subject.recipients).to contain(recipient.iri)
      end
    end

    context "addressed to a local recipient" do
      let(recipient) { local_recipient }

      before_each { activity.to = [recipient.iri] }

      it "does not include the recipient" do
        expect(subject.recipients).not_to contain(recipient.iri)
      end
    end

    context "addressed to a remote recipient" do
      let(recipient) { remote_recipient }

      before_each { activity.to = [recipient.iri] }

      it "does not include the recipient" do
        expect(subject.recipients).not_to contain(recipient.iri)
      end
    end

    context "addressed to a local collection" do
      let(recipient) { local_collection }

      before_each { activity.to = [recipient.iri] }

      it "does not include the collection" do
        expect(subject.recipients).not_to contain(recipient.iri)
      end

      context "of the receiver's followers" do
        let(recipient) { local_collection.assign(iri: "#{receiver.iri}/followers") }

        before_each do
          Relationship::Social::Follow.new(
            actor: local_recipient,
            object: receiver,
            confirmed: true
          ).save
          Relationship::Social::Follow.new(
            actor: remote_recipient,
            object: receiver,
            confirmed: true
          ).save
        end

        context "given a reply" do
          let(original) do
            ActivityPub::Object.new(
              iri: "https://remote/objects/original",
              attributed_to: receiver
            )
          end
          let(reply) do
            ActivityPub::Object.new(
              iri: "https://remote/objects/reply",
              in_reply_to: original
            )
          end

          before_each do
            activity.object_iri = reply.iri
            original.save
            reply.save
          end

          it "does not include the collection" do
            expect(subject.recipients).not_to contain(recipient.iri)
          end

          it "does not include the followers" do
            expect(subject.recipients).not_to contain(local_recipient.iri, remote_recipient.iri)
          end

          context "which is addressed to the local collection" do
            before_each do
              original.to = [recipient.iri]
              reply.to = [recipient.iri]
              original.save
              reply.save
            end

            it "includes the followers" do
              expect(subject.recipients).to contain(local_recipient.iri, remote_recipient.iri)
            end

            context "when follows are not confirmed" do
              before_each do
                Relationship::Social::Follow.where(to_iri: receiver.iri).each do |follow|
                  follow.assign(confirmed: false).save
                end
              end

              it "does not include the followers" do
                expect(subject.recipients).not_to contain(local_recipient.iri, remote_recipient.iri)
              end
            end

            context "when followers have been deleted" do
              before_each do
                local_recipient.delete
                remote_recipient.delete
              end

              it "does not include the recipients" do
                expect(subject.recipients).not_to contain(local_recipient.iri, remote_recipient.iri)
              end
            end

            context "when the original is not attributed to the receiver" do
              before_each do
                original.assign(attributed_to: remote_recipient).save
              end

              it "does not include the followers" do
                expect(subject.recipients).not_to contain(local_recipient.iri, remote_recipient.iri)
              end

              context "but it is itself a reply to another post by the receiver" do
                let(another) do
                  ActivityPub::Object.new(
                    iri: "https://remote/objects/another",
                    attributed_to: receiver,
                    to: [recipient.iri]
                  )
                end

                before_each do
                  original.assign(in_reply_to: another).save
                end

                it "includes the followers" do
                  expect(subject.recipients).to contain(local_recipient.iri, remote_recipient.iri)
                end

                context "unless it doesn't address the local colletion" do
                  before_each do
                    original.to = [remote_collection.iri]
                    original.save
                  end

                  it "does not include the followers" do
                    expect(subject.recipients).not_to contain(local_recipient.iri, remote_recipient.iri)
                  end
                end
              end
            end
          end
        end
      end
    end

    context "addressed to a remote collection" do
      let(recipient) { remote_collection }

      before_each { activity.to = [recipient.iri] }

      it "does not include the collection" do
        expect(subject.recipients).not_to contain(recipient.iri)
      end

      it "does not include the receiver" do
        expect(subject.recipients).not_to contain(receiver.iri)
      end

      context "of the senders's followers" do
        let(sender) do
          ActivityPub::Actor.new(iri: "https://remote/actors/sender", followers: "https://remote/actors/sender/followers")
        end

        let(recipient) { remote_collection.assign(iri: "#{sender.iri}/followers") }

        before_each do
          activity.actor_iri = sender.iri

          HTTP::Client.collections << recipient

          Relationship::Social::Follow.new(
            actor: receiver,
            object: sender,
            confirmed: true
          ).save
        end

        it "includes the receiver" do
          expect(subject.recipients).to contain(receiver.iri)
        end

        context "when follows are not confirmed" do
          before_each do
            Relationship::Social::Follow.where(from_iri: receiver.iri).each do |follow|
              follow.assign(confirmed: false).save
            end
          end

          it "does not include the receiver" do
            expect(subject.recipients).not_to contain(receiver.iri)
          end
        end
      end
    end

    context "addressed to the public collection" do
      PUBLIC = "https://www.w3.org/ns/activitystreams#Public"

      before_each { activity.to = [PUBLIC] }

      it "does not include the collection" do
        expect(subject.recipients).not_to contain(PUBLIC)
      end

      it "does not include the receiver" do
        expect(subject.recipients).not_to contain(receiver.iri)
      end

      context "the receiver is a follower of the sender" do
        let(sender) do
          ActivityPub::Actor.new(iri: "https://remote/actors/sender")
        end

        before_each do
          activity.actor_iri = sender.iri
          Relationship::Social::Follow.new(
            actor: receiver,
            object: sender,
            confirmed: true
          ).save
        end

        it "includes the receiver" do
          expect(subject.recipients).to contain(receiver.iri)
        end
      end
    end
  end

  describe "#deliver" do
    subject do
      described_class.new(
        receiver: receiver,
        activity: activity
      )
    end

    before_each do
      local_recipient.save
      remote_recipient.save
    end

    # handle recipients, instead of only the receiver, since
    # recipients can include the receiver's followers who are part of
    # a threaded conversation.

    alias Notification = Relationship::Content::Notification
    alias Timeline = Relationship::Content::Timeline

    context "when object mentions a local recipient" do
      let(mention) do
        ActivityPub::Object.new(
          iri: "https://remote/objects/mention",
          mentions: [Tag::Mention.new(name: "local recipient", href: local_recipient.iri)]
        )
      end

      before_each do
        activity.object_iri = mention.iri
        HTTP::Client.objects << mention
      end

      it "puts the activity in the recipient's notifications" do
        expect{subject.deliver([local_recipient.iri])}.
          to change{Notification.count(from_iri: local_recipient.iri)}.by(1)
      end
    end

    context "when activity is a create" do
      let!(object) do
        ActivityPub::Object.new(
          iri: "https://remote/objects/object",
          attributed_to: local_recipient
        ).save
      end
      let(activity) do
        ActivityPub::Activity::Create.new(
          iri: "https://remote/activities/create",
          object: object
        )
      end

      it "puts the object in the recipient's timeline" do
        expect{subject.deliver([local_recipient.iri])}.
          to change{Timeline.count(from_iri: local_recipient.iri)}.by(1)
      end

      context "and the object's already in the timeline" do
        before_each do
          Timeline.new(
            owner: local_recipient,
            object: object
          ).save
        end

        it "does not put the object in the recipient's timeline" do
          expect{subject.deliver([local_recipient.iri])}.
            not_to change{Timeline.count(from_iri: local_recipient.iri)}
        end
      end

      context "and the object is a reply" do
        before_each do
          object.assign(
            in_reply_to: ActivityPub::Object.new(
              iri: "https://remote/objects/reply"
            )
          ).save
        end

        it "does not put the object in the recipient's timeline" do
          expect{subject.deliver([local_recipient.iri])}.
            not_to change{Timeline.count(from_iri: local_recipient.iri)}
        end
      end
    end

    context "when activity is an announce" do
      let!(object) do
        ActivityPub::Object.new(
          iri: "https://test.test/objects/object",
          attributed_to: local_recipient
        ).save
      end
      let(activity) do
        ActivityPub::Activity::Announce.new(
          iri: "https://remote/activities/announce",
          object: object
        )
      end

      it "puts the activity in the recipient's notifications" do
        expect{subject.deliver([local_recipient.iri])}.
          to change{Notification.count(from_iri: local_recipient.iri)}.by(1)
      end

      it "puts the object in the recipient's timeline" do
        expect{subject.deliver([local_recipient.iri])}.
          to change{Timeline.count(from_iri: local_recipient.iri)}.by(1)
      end

      context "and the object's already in the timeline" do
        before_each do
          Timeline.new(
            owner: local_recipient,
            object: object
          ).save
        end

        it "does not put the object in the recipient's timeline" do
          expect{subject.deliver([local_recipient.iri])}.
            not_to change{Timeline.count(from_iri: local_recipient.iri)}
        end
      end

      context "and the object is a reply" do
        before_each do
          object.assign(
            in_reply_to: ActivityPub::Object.new(
              iri: "https://remote/objects/reply"
            )
          ).save
        end

        it "puts the object in the recipient's timeline" do
          expect{subject.deliver([local_recipient.iri])}.
            to change{Timeline.count(from_iri: local_recipient.iri)}.by(1)
        end
      end
    end

    context "when activity is a like" do
      let!(object) do
        ActivityPub::Object.new(
          iri: "https://test.test/objects/object",
          attributed_to: local_recipient
        ).save
      end
      let(activity) do
        ActivityPub::Activity::Like.new(
          iri: "https://remote/activities/like",
          object: object
        )
      end

      it "puts the activity in the recipient's notifications" do
        expect{subject.deliver([local_recipient.iri])}.
          to change{Notification.count(from_iri: local_recipient.iri)}.by(1)
      end
    end

    context "when activity is a follow" do
      let(activity) do
        ActivityPub::Activity::Follow.new(
          iri: "https://remote/activities/follow",
          object: local_recipient
        )
      end

      it "puts the activity in the recipient's notifications" do
        expect{subject.deliver([local_recipient.iri])}.
          to change{Notification.count(from_iri: local_recipient.iri)}.by(1)
      end
    end

    it "does not put the object in the recipient's notifications" do
      expect{subject.deliver([local_recipient.iri])}.
        not_to change{Notification.count(from_iri: local_recipient.iri)}
    end

    it "does not put the object in the recipient's timeline" do
      expect{subject.deliver([local_recipient.iri])}.
        not_to change{Timeline.count(from_iri: local_recipient.iri)}
    end

    it "puts the activity in the inbox of a local recipient" do
      subject.deliver([local_recipient.iri])
      expect(Relationship::Content::Inbox.count(from_iri: local_recipient.iri)).to eq(1)
    end

    it "sends the activity to the inbox of a remote recipient" do
      subject.deliver([remote_recipient.iri])
      expect(HTTP::Client.requests).to have("POST #{remote_recipient.inbox}")
    end
  end

  describe "#perform" do
    subject do
      described_class.new(
        receiver: receiver,
        activity: activity
      )
    end

    context "when the object has been deleted" do
      let(activity) do
        ActivityPub::Activity::Delete.new(
          iri: "https://test.test/activities/delete",
          actor_iri: receiver.iri,
          object_iri: "https://deleted",
          to: [receiver.iri]
        )
      end

      it "does not fail" do
        expect{subject.perform}.not_to change{subject.failures}
      end
    end
  end
end
