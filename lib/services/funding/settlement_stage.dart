/// Stages of a settlement operation (Phase 5 plan B6).
enum SettlementStage {
  created,
  quoted,
  reviewed,
  authorizing,
  signed,
  broadcasting,
  funded,
  submitted,
  processing,
  settled,
  refunded,
  failed,
  abandoned,
  notFunded,
  fundingUnknown,
  lateDeposit,
  refunding,
  needsAttention;

  /// Stages before the call that moves funds.
  bool get isBeforeBroadcasting => const {
        SettlementStage.created,
        SettlementStage.quoted,
        SettlementStage.reviewed,
        SettlementStage.authorizing,
        SettlementStage.signed,
      }.contains(this);

  /// Stages no status check can change.
  bool get isTerminal => const {
        SettlementStage.settled,
        SettlementStage.refunded,
        SettlementStage.abandoned,
      }.contains(this);

  /// Whether funds may have left the source account.
  bool get mayHaveMovedFunds =>
      !isBeforeBroadcasting &&
      this != SettlementStage.abandoned &&
      this != SettlementStage.notFunded;

  static SettlementStage? fromName(String? name) {
    for (final stage in values) {
      if (stage.name == name) return stage;
    }
    return null;
  }
}

/// How an operation's funds leave the source account.
enum SettlementFundingKind { spark, bitcoin, evm, relayer, hyperliquid }
