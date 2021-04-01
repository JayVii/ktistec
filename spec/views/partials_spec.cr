require "../../src/models/activity_pub/activity/follow"
require "../../src/models/activity_pub/activity/announce"
require "../../src/models/activity_pub/activity/like"
require "../../src/views/view_helper"

require "../spec_helper/controller"

Spectator.describe "partials" do
  setup_spec

  include Ktistec::Controller
  include Ktistec::ViewHelper

  describe "collection.json.ecr" do
    let(env) do
      HTTP::Server::Context.new(
        HTTP::Request.new("GET", "/collection#{query}"),
        HTTP::Server::Response.new(IO::Memory.new)
      )
    end

    let(collection) do
      Ktistec::Util::PaginatedArray{
        ActivityPub::Object.new(iri: "foo"),
        ActivityPub::Object.new(iri: "bar")
      }
    end

    subject { JSON.parse(render "./src/views/partials/collection.json.ecr") }

    context "when paginated" do
      let(query) { "?page=1&size=2" }

      it "renders a collection page" do
        expect(subject.dig("type")).to eq("OrderedCollectionPage")
      end

      it "contains the id of the collection page" do
        expect(subject.dig("id")).to eq("#{Ktistec.host}/collection?page=1&size=2")
      end

      it "contains a page of items" do
        expect(subject.dig("orderedItems").as_a).to contain_exactly("foo", "bar")
      end

      it "does not contain navigation links" do
        expect(subject.dig?("prev")).to be_nil
        expect(subject.dig?("next")).to be_nil
      end

      context "and on the second page" do
        let(query) { "?page=2&size=2" }

        it "contains a link to the previous page" do
          expect(subject.dig?("prev")).to eq("#{Ktistec.host}/collection?page=1&size=2")
        end
      end

      context "and contains more" do
        before_each { collection.more = true }

        it "contains a link to the next page" do
          expect(subject.dig?("next")).to eq("#{Ktistec.host}/collection?page=2&size=2")
        end
      end
    end

    context "when not paginated" do
      let(query) { "" }

      it "renders a collection" do
        expect(subject.dig("type")).to eq("OrderedCollection")
      end

      it "contains the id of the collection" do
        expect(subject.dig("id")).to eq("#{Ktistec.host}/collection")
      end

      it "does not contain any items" do
        expect(subject.dig?("orderedItems")).to be_nil
      end

      it "contains the first collection page" do
        expect(subject.dig("first", "type")).to eq("OrderedCollectionPage")
      end

      it "contains the first collection page" do
        expect(subject.dig("first", "id")).to eq("#{Ktistec.host}/collection?page=1")
      end

      it "contains the first collection page of items" do
        expect(subject.dig("first", "orderedItems").as_a).to contain_exactly("foo", "bar")
      end

      it "does not contain navigation links" do
        expect(subject.dig?("first", "prev")).to be_nil
        expect(subject.dig?("first", "next")).to be_nil
      end

      context "and contains more" do
        before_each { collection.more = true }

        it "contains a link to the next page" do
          expect(subject.dig?("first", "next")).to eq("#{Ktistec.host}/collection?page=2")
        end
      end
    end
  end

  macro follow(from, to, confirmed = true)
    before_each do
      ActivityPub::Activity::Follow.new(
        iri: "#{{{from}}.origin}/activities/follow",
        actor: {{from}},
        object: {{to}}
      ).save
      {{from}}.follow(
        {{to}},
        confirmed: {{confirmed}},
        visible: true
      ).save
    end
  end

  describe "actor-large.html.slang" do
    let(env) do
      HTTP::Server::Context.new(
        HTTP::Request.new("GET", "/actor"),
        HTTP::Server::Response.new(IO::Memory.new)
      )
    end

    let(actor) do
      ActivityPub::Actor.new(
        iri: "https://remote/actors/foo_bar"
      ).save
    end

    subject do
      begin
        XML.parse_html(render "./src/views/partials/actor-large.html.slang")
      rescue XML::Error
        XML.parse_html("<div/>").document
      end
    end

    context "if anonymous" do
      it "does not render a form" do
        expect(subject.xpath_nodes("//form")).to be_empty
      end
    end

    context "if authenticated" do
      let(account) { register }

      before_each { env.account = account }

      context "if account actor is actor" do
        let(actor) { account.actor }

        it "does not render a form" do
          expect(subject.xpath_nodes("//form")).to be_empty
        end
      end

      context "if following actor" do
        follow(account.actor, actor)

        it "renders a button to unfollow" do
          expect(subject.xpath_string("string(//form//button[@type='submit']/text())")).to eq("Unfollow")
        end
      end

      it "renders a button to follow" do
        expect(subject.xpath_string("string(//form//button[@type='submit']/text())")).to eq("Follow")
      end
    end
  end

  describe "actor-small.html.slang" do
    let(env) do
      HTTP::Server::Context.new(
        HTTP::Request.new("GET", "/actors/foo_bar"),
        HTTP::Server::Response.new(IO::Memory.new)
      )
    end

    let(actor) do
      ActivityPub::Actor.new(
        iri: "https://remote/actors/foo_bar"
      ).save
    end

    subject do
      begin
        XML.parse_html(render "./src/views/partials/actor-small.html.slang")
      rescue XML::Error
        XML.parse_html("<div/>").document
      end
    end

    context "if anonymous" do
      it "does not render a form" do
        expect(subject.xpath_nodes("//form")).to be_empty
      end

      context "and actor is local" do
        before_each { actor.assign(iri: "https://test.test/actors/foo_bar").save }

        it "renders a link to remote follow" do
          expect(subject.xpath_string("string(//form//input[@type='submit']/@value)")).to eq("Follow")
        end
      end
    end

    context "if authenticated" do
      let(account) { register }

      before_each { env.account = account }

      context "if account actor is actor" do
        let(actor) { account.actor }

        it "does not render a form" do
          expect(subject.xpath_nodes("//form")).to be_empty
        end
      end

      # on a page of the actors the actor is following, the actor
      # expects to focus on actions regarding their decision to follow
      # those actors, so don't present accept/reject actions.

      context "and on a page of actors the actor is following" do
        let(env) do
          HTTP::Server::Context.new(
            HTTP::Request.new("GET", "/actors/foo_bar/following"),
            HTTP::Server::Response.new(IO::Memory.new)
          )
        end

        follow(actor, account.actor, confirmed: false)

        context "if already following" do
          follow(account.actor, actor)

          it "renders a button to unfollow" do
            expect(subject.xpath_string("string(//form//button[@type='submit']/text())")).to eq("Unfollow")
          end
        end

        it "renders a button to follow" do
          expect(subject.xpath_string("string(//form//button[@type='submit']/text())")).to eq("Follow")
        end
      end

      # otherwise...

      context "having not accepted or rejected a follow" do
        follow(actor, account.actor, confirmed: false)

        context "but already following" do
          follow(account.actor, actor)

          it "renders a button to accept" do
            expect(subject.xpath_nodes("//form//button[@type='submit']/text()").map(&.text)).to have("Accept")
          end

          it "renders a button to reject" do
            expect(subject.xpath_nodes("//form//button[@type='submit']/text()").map(&.text)).to have("Reject")
          end
        end

        it "renders a button to accept" do
          expect(subject.xpath_nodes("//form//button[@type='submit']/text()").map(&.text)).to have("Accept")
        end

        it "renders a button to reject" do
          expect(subject.xpath_nodes("//form//button[@type='submit']/text()").map(&.text)).to have("Reject")
        end
      end

      context "having accepted or rejected a follow" do
        follow(actor, account.actor, confirmed: true)

        context "and already following" do
          follow(account.actor, actor)

          it "renders a button to unfollow" do
            expect(subject.xpath_string("string(//form//button[@type='submit']/text())")).to eq("Unfollow")
          end
        end

        it "renders a button to follow" do
          expect(subject.xpath_string("string(//form//button[@type='submit']/text())")).to eq("Follow")
        end
      end

      context "when already following" do
        follow(account.actor, actor)

        it "renders a button to unfollow" do
          expect(subject.xpath_string("string(//form//button[@type='submit']/text())")).to eq("Unfollow")
        end
      end

      it "renders a button to follow" do
        expect(subject.xpath_string("string(//form//button[@type='submit']/text())")).to eq("Follow")
      end
    end
  end

  describe "object.html.slang" do
    let(env) do
      HTTP::Server::Context.new(
        HTTP::Request.new("GET", "/object"),
        HTTP::Server::Response.new(IO::Memory.new)
      )
    end

    let(for_thread) { nil }

    subject do
      begin
        XML.parse_html(object_partial(env, object, actor, actor, for_thread: for_thread))
      rescue XML::Error
        XML.parse_html("<div/>").document
      end
    end

    let(account) { register }

    let(actor) { account.actor }
    let!(object) do
      ActivityPub::Object.new(
        iri: "https://test.test/objects/object"
      ).save
    end

    context "if authenticated" do
      before_each { env.account = account }

      context "for approvals" do
        before_each { object.assign(published: Time.utc).save }

        context "on a page of threaded replies" do
          let(env) do
            HTTP::Server::Context.new(
              HTTP::Request.new("GET", "/thread"),
              HTTP::Server::Response.new(IO::Memory.new)
            )
          end

          it "does not render a checkbox to approve" do
            actor.unapprove(object)
            expect(subject.xpath_nodes("//input[@type='checkbox'][@name='public']")).to be_empty
          end

          it "does not render a checkbox to unapprove" do
            actor.approve(object)
            expect(subject.xpath_nodes("//input[@type='checkbox'][@name='public']")).to be_empty
          end

          context "unless in reply to a post by the account's actor" do
            let(original) do
              ActivityPub::Object.new(
                iri: "https://test.test/objects/reply",
                attributed_to: account.actor
              )
            end

            let(for_thread) { [original] }

            before_each do
              object.assign(in_reply_to: original).save
            end

            it "renders a checkbox to approve" do
              actor.unapprove(object)
              expect(subject.xpath_nodes("//input[@type='checkbox'][@name='public']/@checked")).to be_empty
            end

            it "renders a checkbox to unapprove" do
              actor.approve(object)
              expect(subject.xpath_nodes("//input[@type='checkbox'][@name='public']/@checked")).not_to be_empty
            end
          end
        end
      end

      context "and a draft" do
        pre_condition { expect(object.draft?).to be_true }

        it "does not render a button to reply" do
          expect(subject.xpath_nodes("//a/button/text()").map(&.text)).not_to have("Reply")
        end

        it "does not render a button to like" do
          expect(subject.xpath_nodes("//form//button[@type='submit']/text()").map(&.text)).not_to have("Like")
        end

        it "does not render a button to share" do
          expect(subject.xpath_nodes("//form//button[@type='submit']/text()").map(&.text)).not_to have("Share")
        end

        it "renders a button to delete" do
          expect(subject.xpath_nodes("//form//button[@type='submit']/text()").map(&.text)).to have("Delete")
        end

        it "renders a button to edit" do
          expect(subject.xpath_nodes("//a/button/text()").map(&.text)).to have("Edit")
        end
      end
    end
  end

  describe "reply.html.slang" do
    let(env) do
      HTTP::Server::Context.new(
        HTTP::Request.new("GET", "/object"),
        HTTP::Server::Response.new(IO::Memory.new)
      )
    end

    subject do
      begin
        XML.parse_html(render "./src/views/objects/reply.html.slang")
      rescue XML::Error
        XML.parse_html("<div/>").document
      end
    end

    context "if authenticated" do
      let(account) { register }

      before_each { env.account = account }

      let(actor) do
        ActivityPub::Actor.new(
          iri: "https://remote/actors/actor",
          username: "actor"
        ).save
      end
      let(object) do
        ActivityPub::Object.new(
          iri: "https://remote/objects/object",
          attributed_to: actor,
          in_reply_to: ActivityPub::Object.new(
            iri: "https://test.test/objects/object",
            attributed_to: account.actor
          )
        ).save
      end

      it "addresses (to) the author of the replied to post" do
        expect(subject.xpath_nodes("//form//input[@name='to']/@value").first.text).to eq(actor.iri)
      end

      it "addresses (cc) the authors of the posts in the thread" do
        expect(subject.xpath_nodes("//form//input[@name='cc']/@value").first.text).to eq(account.actor.iri)
      end

      it "prepopulates editor with mentions" do
        expect(subject.xpath_nodes("//form//input[@name='content']/@value").first.text).
          to eq("@#{actor.account_uri} @#{account.actor.account_uri} ")
      end
    end
  end
end
