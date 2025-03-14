defmodule Type.LazyInitTest.PredicateNested do
  use Ash.Type.NewType, subtype_of: Type.LazyInitTest.Predicate, lazy_init?: true
end
