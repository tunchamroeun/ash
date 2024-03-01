defmodule Ash.Test.Actions.AggregateTest do
  @moduledoc false
  use ExUnit.Case, async: true

  require Ash.Query

  alias Ash.Test.Domain, as: Domain

  defmodule Comment do
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    actions do
      defaults [:create, :read, :update, :destroy]
    end

    attributes do
      uuid_primary_key :id

      attribute :public, :boolean do
        public?(true)
        default false
      end

      attribute :thing, :string do
        public?(true)
      end

      attribute :thing2, :decimal do
        public?(true)
      end

      attribute :thing3, :integer do
        public?(true)
      end
    end

    relationships do
      belongs_to :post, Ash.Test.Actions.AggregateTest.Post do
        attribute_writable? true
        public?(true)
      end
    end

    policies do
      policy always() do
        authorize_if expr(public == true)
      end
    end
  end

  defmodule Post do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(true)
    end

    actions do
      defaults [:create, :read, :update, :destroy]
      read :unpublic

      read :with_foo do
        prepare build(filter: [foo: true])
      end
    end

    attributes do
      uuid_primary_key :id

      attribute :title, :string do
        public?(true)
      end

      attribute :public, :boolean do
        public?(true)
        default false
      end

      attribute :tenant, :string do
        public?(true)
      end

      attribute :thing, :string do
        public?(true)
      end

      attribute :foo, :boolean, default: false
    end

    multitenancy do
      global? true
      strategy :attribute
      attribute :tenant
    end

    aggregates do
      count :count_of_comments, :comments do
        public? false
      end

      count :count_of_posts, [:comments, :post] do
        public? false
      end

      count :count_of_comment_posts_with_matching_things, [:comments, :post] do
        public? false
        join_filter(:comments, expr(parent(thing) == thing))
      end

      count :count_of_comments_unauthorized, :comments do
        public? true
        authorize? false
      end

      min :min_of_thing2, :comments, :thing2 do
        public? true
        authorize? false
      end

      max :max_of_thing2, :comments, :thing2 do
        public? true
        authorize? false
      end

      avg :average_of_thing2, :comments, :thing2 do
        public? true
        authorize? false
      end

      min :min_of_thing3, :comments, :thing3 do
        public? true
        authorize? false
      end

      max :max_of_thing3, :comments, :thing3 do
        public? true
        authorize? false
      end

      avg :average_of_thing3, :comments, :thing3 do
        public? true
        authorize? false
      end
    end

    relationships do
      has_many :comments, Comment do
        public?(true)
      end
    end

    policies do
      policy action(:read) do
        authorize_if expr(public == true)
      end

      policy action(:unpublic) do
        authorize_if expr(public == false)
      end
    end
  end

  describe "Domain.aggregate" do
    test "allows counting records" do
      assert %{count: 0} = Domain.aggregate!(Post, {:count, :count}, authorize?: false)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Domain.create!(authorize?: false)

      assert %{count: 1} = Domain.aggregate!(Post, {:count, :count}, authorize?: false)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Domain.create!(authorize?: false)

      assert %{count: 2} = Domain.aggregate!(Post, {:count, :count}, authorize?: false)
    end

    test "honors tenant" do
      assert %{count: 0} = Domain.aggregate!(Post, {:count, :count}, authorize?: false)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", tenant: "foo"})
      |> Domain.create!(authorize?: false)

      assert %{count: 1} =
               Domain.aggregate!(Post, {:count, :count}, tenant: "foo", authorize?: false)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", tenant: "foo"})
      |> Domain.create!(authorize?: false)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", tenant: "bar"})
      |> Domain.create!(authorize?: false)

      assert %{count: 2} =
               Domain.aggregate!(Post, {:count, :count}, tenant: "foo", authorize?: false)

      assert %{count: 3} = Domain.aggregate!(Post, {:count, :count}, authorize?: false)
    end

    test "runs authorization" do
      assert %{count: 0} = Domain.aggregate!(Post, {:count, :count}, authorize?: true)

      assert 0 = Domain.count!(Post, authorize?: true)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Domain.create!(authorize?: false)

      assert %{count: 0} = Domain.aggregate!(Post, {:count, :count}, authorize?: true)
      assert 0 = Domain.count!(Post, authorize?: true)

      assert %{count: 1} =
               Post
               |> Ash.Query.for_read(:unpublic)
               |> Domain.aggregate!({:count, :count}, actor: nil)

      assert %{count: 1} =
               Domain.aggregate!(Post, {:count, :count}, actor: nil, action: :unpublic)

      assert 1 = Domain.count!(Post, actor: nil, action: :unpublic, authorize?: true)
      assert 0 = Domain.count!(Post, authorize?: true)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", public: true})
      |> Domain.create!(authorize?: false)

      assert %{count: 1} = Domain.aggregate!(Post, {:count, :count}, authorize?: true)
      assert 1 = Domain.count!(Post, authorize?: true)
    end

    test "use custom actions from the query" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "without foo", foo: false})
      |> Api.create!()

      assert false ==
               Post
               |> Ash.Query.for_read(:with_foo)
               |> Api.exists?()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "with foo", foo: true})
      |> Api.create!()

      assert 1 ==
               Post
               |> Ash.Query.for_read(:with_foo)
               |> Api.count!()

      assert ["with foo"] ==
               Post
               |> Ash.Query.for_read(:with_foo)
               |> Api.list!(:title)
    end
  end

  describe "aggregate loading" do
    test "loading aggregates can be authorized or not" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title", public: true})
        |> Domain.create!(authorize?: false)

      Comment
      |> Ash.Changeset.for_create(:create, %{post_id: post.id, public: true})
      |> Domain.create!(authorize?: false)

      Comment
      |> Ash.Changeset.for_create(:create, %{post_id: post.id, public: false})
      |> Domain.create!(authorize?: false)

      assert %{count_of_comments: 2, count_of_comments_unauthorized: 2} =
               Domain.load!(post, [:count_of_comments, :count_of_comments_unauthorized],
                 authorize?: false
               )

      assert %{count_of_comments: 1, count_of_comments_unauthorized: 2} =
               Domain.load!(post, [:count_of_comments, :count_of_comments_unauthorized],
                 authorize?: true
               )
    end

    test "join filters are applied" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "title",
          public: true,
          thing: "not the same"
        })
        |> Domain.create!(authorize?: false)

      Comment
      |> Ash.Changeset.for_create(:create, %{
        post_id: post.id,
        public: true,
        thing: "doesnt match"
      })
      |> Domain.create!(authorize?: false)

      assert Domain.load!(post, :count_of_comment_posts_with_matching_things, authorize?: false).count_of_comment_posts_with_matching_things ==
               0

      Comment
      |> Ash.Changeset.for_create(:create, %{
        post_id: post.id,
        public: true,
        thing: "not the same"
      })
      |> Domain.create!(authorize?: false)

      assert Domain.load!(post, :count_of_comment_posts_with_matching_things, authorize?: false).count_of_comment_posts_with_matching_things ==
               1
    end

    test "aggregations on decimal fields succeed" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "title",
          public: true,
          thing: "not the same"
        })
        |> Domain.create!(authorize?: false)

      Comment
      |> Ash.Changeset.for_create(:create, %{
        post_id: post.id,
        public: true,
        thing: "doesnt match",
        thing2: 10,
        thing3: 100
      })
      |> Domain.create!(authorize?: false)

      Comment
      |> Ash.Changeset.for_create(:create, %{
        post_id: post.id,
        public: true,
        thing: "doesnt match",
        thing2: 20,
        thing3: 200
      })
      |> Domain.create!(authorize?: false)

      Comment
      |> Ash.Changeset.for_create(:create, %{
        post_id: post.id,
        public: true,
        thing: "doesnt match",
        thing2: nil,
        thing3: nil
      })
      |> Domain.create!(authorize?: false)

      assert Decimal.eq?(
               Domain.load!(post, :min_of_thing2, authorize?: false).min_of_thing2,
               Decimal.new(10)
             )

      assert Decimal.eq?(
               Domain.load!(post, :max_of_thing2, authorize?: false).max_of_thing2,
               Decimal.new(20)
             )

      assert Decimal.eq?(
               Domain.load!(post, :average_of_thing2, authorize?: false).average_of_thing2,
               Decimal.new(15)
             )

      assert Domain.load!(post, :min_of_thing3, authorize?: false).min_of_thing3 == 100
      assert Domain.load!(post, :max_of_thing3, authorize?: false).max_of_thing3 == 200
      assert Domain.load!(post, :average_of_thing3, authorize?: false).average_of_thing3 == 150
    end
  end
end
