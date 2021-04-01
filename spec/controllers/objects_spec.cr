require "../../src/controllers/objects"

require "../spec_helper/controller"

Spectator.describe ObjectsController do
  setup_spec

  let(actor) { register.actor }

  let(author) do
    ActivityPub::Actor.new(
      iri: "https://nowhere/#{random_string}"
    ).save
  end
  let!(visible) do
    ActivityPub::Object.new(
      iri: "https://test.test/objects/#{random_string}",
      attributed_to: author,
      published: Time.utc,
      visible: true
    ).save
  end
  let!(notvisible) do
    ActivityPub::Object.new(
      iri: "https://test.test/objects/#{random_string}",
      attributed_to: author,
      published: Time.utc,
      visible: false
    ).save
  end
  let!(remote) do
    ActivityPub::Object.new(
      iri: "https://remote/#{random_string}",
      attributed_to: author,
      published: Time.utc
    ).save
  end
  let!(draft) do
    ActivityPub::Object.new(
      iri: "https://test.test/objects/#{random_string}",
      content: "this is a test",
      attributed_to: actor,
      visible: false
    ).save
  end

  macro put_in_inbox(object)
    Relationship::Content::Inbox.new(
      from_iri: actor.iri,
      to_iri: ActivityPub::Activity.new(
        iri: "https://test.test/activities/#{random_string}",
        actor_iri: actor.iri,
        object_iri: {{object}}.iri
      ).save.iri
    ).save
  end

  macro put_in_outbox(object)
    Relationship::Content::Outbox.new(
      from_iri: actor.iri,
      to_iri: ActivityPub::Activity.new(
        iri: "https://test.test/activities/#{random_string}",
        actor_iri: actor.iri,
        object_iri: {{object}}.iri
      ).save.iri
    ).save
  end

  ACCEPT_HTML = HTTP::Headers{"Accept" => "text/html"}
  ACCEPT_JSON = HTTP::Headers{"Accept" => "application/json"}
  FORM_DATA = HTTP::Headers{"Accept" => "text/html", "Content-Type" => "application/x-www-form-urlencoded"}
  JSON_DATA = HTTP::Headers{"Accept" => "application/json", "Content-Type" => "application/json"}

  describe "GET /actors/:username/drafts" do
    it "returns 401 if not authorized" do
      get "/actors/0/drafts"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "succeeds" do
        get "/actors/#{actor.username}/drafts", ACCEPT_HTML
        expect(response.status_code).to eq(200)
      end

      it "succeeds" do
        get "/actors/#{actor.username}/drafts", ACCEPT_JSON
        expect(response.status_code).to eq(200)
      end

      it "renders the collection" do
        get "/actors/#{actor.username}/drafts", ACCEPT_HTML
        expect(XML.parse_html(response.body).xpath_nodes("//article/@id").map(&.text)).to contain_exactly("object-#{draft.id}")
      end

      it "renders the collection" do
        get "/actors/#{actor.username}/drafts", ACCEPT_JSON
        expect(JSON.parse(response.body).dig("items").as_a.map(&.dig("id"))).to contain_exactly(draft.iri)
      end

      it "returns 403 if not the authorized account" do
        get "/actors/#{register.actor.username}/drafts"
        expect(response.status_code).to eq(403)
      end
    end
  end

  describe "POST /objects" do
    it "returns 401 if not authorized" do
      post "/objects"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "succeeds" do
        post "/objects", FORM_DATA, "content="
        expect(response.status_code).to eq(302)
      end

      it "succeeds" do
        post "/objects", JSON_DATA, %Q|{"content":""}|
        expect(response.status_code).to eq(201)
      end

      it "creates an object" do
        expect{post "/objects", FORM_DATA, "content=foo+bar"}.
          to change{ActivityPub::Object::Note.count(content: "foo bar", attributed_to_iri: actor.iri)}.by(1)
      end

      it "creates an object" do
        expect{post "/objects", JSON_DATA, %Q|{"content":"foo bar"}|}.
          to change{ActivityPub::Object::Note.count(content: "foo bar", attributed_to_iri: actor.iri)}.by(1)
      end
    end
  end

  describe "GET /objects/:id" do
    it "succeeds" do
      get "/objects/#{visible.uid}", ACCEPT_HTML
      expect(response.status_code).to eq(200)
    end

    it "succeeds" do
      get "/objects/#{visible.uid}", ACCEPT_JSON
      expect(response.status_code).to eq(200)
    end

    it "renders the object" do
      get "/objects/#{visible.uid}", ACCEPT_HTML
      expect(XML.parse_html(response.body).xpath_nodes("//article/@id").first.text).to eq("object-#{visible.id}")
    end

    it "renders the object" do
      get "/objects/#{visible.uid}", ACCEPT_JSON
      expect(JSON.parse(response.body)["id"]).to eq(visible.iri)
    end

    it "returns 404 if object is a draft" do
      get "/objects/#{draft.uid}"
      expect(response.status_code).to eq(404)
    end

    it "returns 404 if object is not visible" do
      get "/objects/#{notvisible.uid}"
      expect(response.status_code).to eq(404)
    end

    it "returns 404 if object is remote" do
      get "/objects/#{remote.uid}"
      expect(response.status_code).to eq(404)
    end

    it "returns 404 if object does not exist" do
      get "/objects/0"
      expect(response.status_code).to eq(404)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "redirects if draft" do
        get "/objects/#{draft.uid}"
        expect(response.status_code).to eq(302)
      end

      context "but not the author" do
        before_each { draft.assign(attributed_to: author).save }

        it "returns 404" do
          get "/objects/#{draft.uid}"
          expect(response.status_code).to eq(404)
        end
      end

      context "and it's in the user's inbox" do
        before_each do
          [visible, notvisible, remote].each { |object| put_in_inbox(object) }
        end

        it "succeeds if local" do
          [visible, notvisible].each do |object|
            get "/objects/#{object.uid}", ACCEPT_HTML
            expect(response.status_code).to eq(200)
          end
        end

        it "succeeds if local" do
          [visible, notvisible].each do |object|
            get "/objects/#{object.uid}", ACCEPT_JSON
            expect(response.status_code).to eq(200)
          end
        end

        it "returns 404 if object is remote" do
          get "/objects/#{remote.uid}"
          expect(response.status_code).to eq(404)
        end
      end
    end
  end

  describe "GET /objects/:id/thread" do
    it "succeeds" do
      get "/objects/#{visible.uid}/thread", ACCEPT_HTML
      expect(response.status_code).to eq(200)
    end

    it "succeeds" do
      get "/objects/#{visible.uid}/thread", ACCEPT_JSON
      expect(response.status_code).to eq(200)
    end

    it "renders the collection" do
      get "/objects/#{visible.uid}/thread", ACCEPT_HTML
      expect(XML.parse_html(response.body).xpath_nodes("//article/@id").map(&.text)).to contain_exactly("object-#{visible.id}")
    end

    it "renders the collection" do
      get "/objects/#{visible.uid}/thread", ACCEPT_JSON
      expect(JSON.parse(response.body).dig("items").as_a.map(&.dig("id"))).to contain_exactly(visible.iri)
    end

    it "returns 404 if object is a draft" do
      get "/objects/#{draft.uid}/thread"
      expect(response.status_code).to eq(404)
    end

    it "returns 404 if object is not visible" do
      get "/objects/#{notvisible.uid}/thread"
      expect(response.status_code).to eq(404)
    end

    it "returns 404 if object is remote" do
      get "/objects/#{remote.uid}/thread"
      expect(response.status_code).to eq(404)
    end

    it "returns 404 if object does not exist" do
      get "/objects/0/thread"
      expect(response.status_code).to eq(404)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "redirects if draft" do
        get "/objects/#{draft.uid}/thread"
        expect(response.status_code).to eq(302)
      end

      context "but not the author" do
        before_each { draft.assign(attributed_to: author).save }

        it "returns 404" do
          get "/objects/#{draft.uid}/thread"
          expect(response.status_code).to eq(404)
        end
      end

      context "and it's in the user's inbox" do
        before_each do
          [visible, notvisible, remote].each { |object| put_in_inbox(object) }
        end

        it "succeeds if local" do
          [visible, notvisible].each do |object|
            get "/objects/#{object.uid}/thread", ACCEPT_HTML
            expect(response.status_code).to eq(200)
          end
        end

        it "succeeds if local" do
          [visible, notvisible].each do |object|
            get "/objects/#{object.uid}/thread", ACCEPT_JSON
            expect(response.status_code).to eq(200)
          end
        end

        it "returns 404 if object is remote" do
          get "/objects/#{remote.uid}/thread"
          expect(response.status_code).to eq(404)
        end
      end
    end

    context "with replies" do
      before_each do
        notvisible.assign(in_reply_to: visible).save
      end

      it "renders the collection" do
        get "/objects/#{visible.uid}/thread", ACCEPT_HTML
        expect(XML.parse_html(response.body).xpath_nodes("//article/@id").map(&.text)).to contain_exactly("object-#{visible.id}")
      end

      it "renders the collection" do
        get "/objects/#{visible.uid}/thread", ACCEPT_JSON
        expect(JSON.parse(response.body).dig("items").as_a.map(&.dig("id"))).to contain_exactly(visible.iri)
      end

      context "that are approved" do
        before_each do
          visible.attributed_to.approve(notvisible)
        end

        it "renders the collection" do
          get "/objects/#{visible.uid}/thread", ACCEPT_HTML
          expect(XML.parse_html(response.body).xpath_nodes("//article/@id").map(&.text)).to contain_exactly("object-#{visible.id}", "object-#{notvisible.id}")
        end

        it "renders the collection" do
          get "/objects/#{visible.uid}/thread", ACCEPT_JSON
          expect(JSON.parse(response.body).dig("items").as_a.map(&.dig("id"))).to contain_exactly(visible.iri, notvisible.iri)
        end
      end
    end
  end

  describe "GET /objects/:id/edit" do
    it "returns 401 if not authorized" do
      get "/objects/0/edit"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "succeeds" do
        get "/objects/#{draft.uid}/edit", ACCEPT_HTML
        expect(response.status_code).to eq(200)
      end

      it "succeeds" do
        get "/objects/#{draft.uid}/edit", ACCEPT_JSON
        expect(response.status_code).to eq(200)
      end

      it "renders a form with the object" do
        get "/objects/#{draft.uid}/edit", ACCEPT_HTML
        expect(XML.parse_html(response.body).xpath_nodes("//form/@id").first.text).to eq("object-#{draft.id}")
      end

      it "renders a button that submits to the outbox path" do
        get "/objects/#{draft.uid}/edit", ACCEPT_HTML
        expect(XML.parse_html(response.body).xpath_nodes("//form[@id]//input[contains(@value,'Post')]/@action").first.text).to eq("/actors/#{actor.username}/outbox")
      end

      it "renders a button that submits to the object update path" do
        get "/objects/#{draft.uid}/edit", ACCEPT_HTML
        expect(XML.parse_html(response.body).xpath_nodes("//form[@id]//input[contains(@value,'Save')]/@action").first.text).to eq("/objects/#{draft.uid}")
      end

      it "renders an input with the draft content" do
        get "/objects/#{draft.uid}/edit", ACCEPT_HTML
        expect(XML.parse_html(response.body).xpath_nodes("//form//input[@name='content']/@value").first.text).to eq("this is a test")
      end

      it "renders the object" do
        get "/objects/#{draft.uid}/edit", ACCEPT_JSON
        expect(JSON.parse(response.body)["id"]).to eq(draft.iri)
      end

      it "returns 404 if not a draft" do
        [visible, notvisible, remote].each do |object|
          get "/objects/#{object.uid}/edit"
          expect(response.status_code).to eq(404)
        end
      end

      it "returns 404 if object does not exist" do
        get "/objects/0/edit"
        expect(response.status_code).to eq(404)
      end
    end
  end

  describe "POST /objects/:id" do
    it "returns 401 if not authorized" do
      post "/objects/0"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "succeeds" do
        post "/objects/#{draft.uid}", FORM_DATA, "content="
        expect(response.status_code).to eq(302)
      end

      it "succeeds" do
        post "/objects/#{draft.uid}", JSON_DATA, %Q|{"content":""}|
        expect(response.status_code).to eq(302)
      end

      it "changes the content" do
        expect{post "/objects/#{draft.uid}", FORM_DATA, "content=foo+bar"}.
          to change{ActivityPub::Object.find(draft.id).content}
      end

      it "changes the content" do
        expect{post "/objects/#{draft.uid}", JSON_DATA, %Q|{"content":"foo bar"}|}.
          to change{ActivityPub::Object.find(draft.id).content}
      end

      it "returns 404 if not a draft" do
        [visible, notvisible, remote].each do |object|
          post "/objects/#{object.uid}"
          expect(response.status_code).to eq(404)
        end
      end

      it "returns 404 if object does not exist" do
        post "/objects/0"
        expect(response.status_code).to eq(404)
      end
    end
  end

  describe "DELETE /objects/:id" do
    it "returns 401 if not authorized" do
      delete "/objects/0"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "succeeds" do
        delete "/objects/#{draft.uid}", FORM_DATA
        expect(response.status_code).to eq(302)
      end

      it "succeeds" do
        delete "/objects/#{draft.uid}", JSON_DATA
        expect(response.status_code).to eq(302)
      end

      it "deletes the object" do
        expect{delete "/objects/#{draft.uid}", FORM_DATA}.
          to change{ActivityPub::Object.count(id: draft.id)}.by(-1)
      end

      it "deletes the object" do
        expect{delete "/objects/#{draft.uid}", JSON_DATA}.
          to change{ActivityPub::Object.count(id: draft.id)}.by(-1)
      end

      it "returns 404 if not a draft" do
        [visible, notvisible, remote].each do |object|
          delete "/objects/#{object.uid}"
          expect(response.status_code).to eq(404)
        end
      end

      it "returns 404 if object does not exist" do
        delete "/objects/0"
        expect(response.status_code).to eq(404)
      end
    end
  end

  describe "GET /remote/objects/:id" do
    it "returns 401 if not authorized" do
      get "/remote/objects/0"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "succeeds" do
        get "/remote/objects/#{visible.id}", ACCEPT_HTML
        expect(response.status_code).to eq(200)
      end

      it "succeeds" do
        get "/remote/objects/#{visible.id}", ACCEPT_JSON
        expect(response.status_code).to eq(200)
      end

      it "renders the object" do
        get "/remote/objects/#{visible.id}", ACCEPT_HTML
        expect(XML.parse_html(response.body).xpath_nodes("//article/@id").first.text).to eq("object-#{visible.id}")
      end

      it "renders the object" do
        get "/remote/objects/#{visible.id}", ACCEPT_JSON
        expect(JSON.parse(response.body)["id"]).to eq(visible.iri)
      end

      it "returns 404 if object is a draft" do
        get "/remote/objects/#{draft.id}"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object is not visible" do
        get "/remote/objects/#{notvisible.id}"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object is remote" do
        get "/remote/objects/#{remote.id}"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object does not exist" do
        get "/remote/objects/0"
        expect(response.status_code).to eq(404)
      end

      context "and it's in the user's inbox" do
        before_each do
          [visible, notvisible, remote].each { |object| put_in_inbox(object) }
        end

        it "succeeds" do
          [visible, notvisible, remote].each do |object|
            get "/remote/objects/#{object.id}", ACCEPT_HTML
            expect(response.status_code).to eq(200)
          end
        end

        it "succeeds" do
          [visible, notvisible, remote].each do |object|
            get "/remote/objects/#{object.id}", ACCEPT_JSON
            expect(response.status_code).to eq(200)
          end
        end
      end
    end
  end

  describe "GET /remote/objects/:id/thread" do
    it "returns 401" do
      get "/remote/objects/0/thread"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "succeeds" do
        get "/remote/objects/#{visible.id}/thread", ACCEPT_HTML
        expect(response.status_code).to eq(200)
      end

      it "succeeds" do
        get "/remote/objects/#{visible.id}/thread", ACCEPT_JSON
        expect(response.status_code).to eq(200)
      end

      it "renders the collection" do
        get "/remote/objects/#{visible.id}/thread", ACCEPT_HTML
        expect(XML.parse_html(response.body).xpath_nodes("//article/@id").map(&.text)).to contain_exactly("object-#{visible.id}")
      end

      it "renders the collection" do
        get "/remote/objects/#{visible.id}/thread", ACCEPT_JSON
        expect(JSON.parse(response.body).dig("items").as_a.map(&.dig("id"))).to contain_exactly(visible.iri)
      end

      it "returns 404 if object is a draft" do
        get "/remote/objects/#{draft.id}/thread"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object is not visible" do
        get "/remote/objects/#{notvisible.id}/thread"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object is remote" do
        get "/remote/objects/#{remote.id}/thread"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object does not exist" do
        get "/remote/objects/0/thread"
        expect(response.status_code).to eq(404)
      end

      context "and it's in the user's inbox" do
        before_each do
          [visible, notvisible, remote].each { |object| put_in_inbox(object) }
        end

        it "succeeds" do
          [visible, notvisible, remote].each do |object|
            get "/remote/objects/#{object.id}/thread", ACCEPT_HTML
            expect(response.status_code).to eq(200)
          end
        end

        it "succeeds" do
          [visible, notvisible, remote].each do |object|
            get "/remote/objects/#{object.id}/thread", ACCEPT_JSON
            expect(response.status_code).to eq(200)
          end
        end
      end

      context "with replies" do
        before_each do
          notvisible.assign(in_reply_to: visible).save
        end

        it "renders the collection" do
          get "/remote/objects/#{visible.id}/thread", ACCEPT_HTML
          expect(XML.parse_html(response.body).xpath_nodes("//article/@id").map(&.text)).to contain_exactly("object-#{visible.id}", "object-#{notvisible.id}")
        end

        it "renders the collection" do
          get "/remote/objects/#{visible.id}/thread", ACCEPT_JSON
          expect(JSON.parse(response.body).dig("items").as_a.map(&.dig("id"))).to contain_exactly(visible.iri, notvisible.iri)
        end
      end
    end
  end

  describe "GET /remote/objects/:id/replies" do
    it "returns 401" do
      get "/remote/objects/0/replies"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      it "succeeds" do
        get "/remote/objects/#{visible.id}/replies"
        expect(response.status_code).to eq(200)
      end

      it "renders the object" do
        get "/remote/objects/#{visible.id}/replies"
        expect(XML.parse_html(response.body).xpath_nodes("//article/@id").first.text).to eq("object-#{visible.id}")
      end

      it "renders the form" do
        get "/remote/objects/#{visible.id}/replies"
        expect(XML.parse_html(response.body).xpath_nodes("//trix-editor")).not_to be_empty
      end

      let(other) do
        ActivityPub::Actor.new(
          iri: "https://nowhere/#{random_string}"
        ).save
      end
      let(parent) do
        ActivityPub::Object.new(
          iri: "https://test.test/objects/#{random_string}",
          attributed_to: other,
          visible: true
        ).save
      end

      before_each do
        visible.assign(in_reply_to: parent).save
      end

      it "addresses (to) the author of the object" do
        get "/remote/objects/#{visible.id}/replies"
        expect(XML.parse_html(response.body).xpath_nodes("//form/input[@name='to']/@value").first.text).to eq(author.iri)
      end

      it "addresses (cc) the other authors in the thread" do
        get "/remote/objects/#{visible.id}/replies"
        expect(XML.parse_html(response.body).xpath_nodes("//form/input[@name='cc']/@value").first.text).to eq(other.iri)
      end

      it "returns 404 if object is a draft" do
        get "/remote/objects/#{draft.id}/replies"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object is not visible" do
        get "/remote/objects/#{notvisible.id}/replies"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object is remote" do
        get "/remote/objects/#{remote.id}/replies"
        expect(response.status_code).to eq(404)
      end

      it "returns 404 if object does not exist" do
        get "/remote/objects/0/replies"
        expect(response.status_code).to eq(404)
      end
    end
  end

  describe "POST /remote/objects/:id/approve" do
    it "returns 401" do
      post "/remote/objects/0/approve"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      before_each { actor.unapprove(remote) }

      it "returns 404" do
        post "/remote/objects/#{remote.id}/approve"
        expect(response.status_code).to eq(404)
      end

      context "and it's in the actor's inbox" do
        before_each { put_in_inbox(remote) }

        it "succeeds" do
          post "/remote/objects/#{remote.id}/approve"
          expect(response.status_code).to eq(302)
        end

        it "approves the object" do
          expect{post "/remote/objects/#{remote.id}/approve"}.
            to change{remote.approved_by?(actor)}
        end

        context "but it's already approved" do
          before_each { actor.approve(remote) }

          it "returns 400" do
            post "/remote/objects/#{remote.id}/approve"
            expect(response.status_code).to eq(400)
          end
        end
      end

      context "and it's in the actor's outbox" do
        before_each { put_in_outbox(remote) }

        it "succeeds" do
          post "/remote/objects/#{remote.id}/approve"
          expect(response.status_code).to eq(302)
        end

        it "approves the object" do
          expect{post "/remote/objects/#{remote.id}/approve"}.
            to change{remote.approved_by?(actor)}
        end

        context "but it's already approved" do
          before_each { actor.approve(remote) }

          it "returns 400" do
            post "/remote/objects/#{remote.id}/approve"
            expect(response.status_code).to eq(400)
          end
        end
      end

      it "returns 404 if object does not exist" do
        post "/remote/objects/0/approve"
        expect(response.status_code).to eq(404)
      end
    end
  end

  describe "POST /remote/objects/:id/unapprove" do
    it "returns 401" do
      post "/remote/objects/0/unapprove"
      expect(response.status_code).to eq(401)
    end

    context "when authorized" do
      sign_in(as: actor.username)

      before_each { actor.approve(remote) }

      it "returns 404" do
        post "/remote/objects/#{remote.id}/unapprove"
        expect(response.status_code).to eq(404)
      end

      context "and it's in the actor's inbox" do
        before_each { put_in_inbox(remote) }

        it "succeeds" do
          post "/remote/objects/#{remote.id}/unapprove"
          expect(response.status_code).to eq(302)
        end

        it "unapproves the object" do
          expect{post "/remote/objects/#{remote.id}/unapprove"}.
            to change{remote.approved_by?(actor)}
        end

        context "but it's already unapproved" do
          before_each { actor.unapprove(remote) }

          it "returns 400" do
            post "/remote/objects/#{remote.id}/unapprove"
            expect(response.status_code).to eq(400)
          end
        end
      end

      context "and it's in the actor's outbox" do
        before_each { put_in_outbox(remote) }

        it "succeeds" do
          post "/remote/objects/#{remote.id}/unapprove"
          expect(response.status_code).to eq(302)
        end

        it "unapproves the object" do
          expect{post "/remote/objects/#{remote.id}/unapprove"}.
            to change{remote.approved_by?(actor)}
        end

        context "but it's already unapproved" do
          before_each { actor.unapprove(remote) }

          it "returns 400" do
            post "/remote/objects/#{remote.id}/unapprove"
            expect(response.status_code).to eq(400)
          end
        end
      end

      it "returns 404 if object does not exist" do
        post "/remote/objects/0/unapprove"
        expect(response.status_code).to eq(404)
      end
    end
  end
end
