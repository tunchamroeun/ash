defmodule Type.LazyInitTest.Predicate do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        condition: [
          type: :string
        ],
        field: [
          type: :string
        ],
        operator: [
          type: :string
        ],
        value: [
          type: :string
        ],
        predicates: [
          type: {:array, Type.LazyInitTest.PredicateNested}
        ]
      ]
    ]

  def graphql_type(_), do: :predicate
  def graphql_input_type(_), do: :predicate_input
end
