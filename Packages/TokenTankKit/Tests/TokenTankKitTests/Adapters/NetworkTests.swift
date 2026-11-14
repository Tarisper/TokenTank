import Testing

/// Parent suite serializing all network-dependent adapter tests: they share the
/// static `URLProtocolStub` state.
@Suite(.serialized)
struct NetworkTests {}
