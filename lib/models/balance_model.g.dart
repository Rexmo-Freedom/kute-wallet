// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'balance_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WalletBalanceAdapter extends TypeAdapter<WalletBalance> {
  @override
  final typeId = 26;

  @override
  WalletBalance read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WalletBalance(
      onChainBtcBalance: (fields[0] as num).toInt(),
      sparkBitcoinbalance: (fields[1] as num).toInt(),
      usdbBalance: fields[2] == null ? 0 : (fields[2] as num).toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, WalletBalance obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.onChainBtcBalance)
      ..writeByte(1)
      ..write(obj.sparkBitcoinbalance)
      ..writeByte(2)
      ..write(obj.usdbBalance);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalletBalanceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
