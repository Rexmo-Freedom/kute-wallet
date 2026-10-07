// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'swap_order_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SwapOrderAdapter extends TypeAdapter<SwapOrder> {
  @override
  final typeId = 31;

  @override
  SwapOrder read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SwapOrder(
      id: fields[0] as String,
      coinFrom: fields[1] as String,
      networkFrom: fields[2] as String,
      coinTo: fields[3] as String,
      networkTo: fields[4] as String,
      depositAddress: fields[5] as String,
      depositExtraId: fields[6] as String?,
      depositAmount: fields[7] as String,
      withdrawalAmount: fields[8] as String,
      status: fields[9] as String,
      timestamp: (fields[10] as num).toInt(),
      withdrawalAddress: fields[11] as String,
      depositMin: fields[12] as String,
      depositMax: fields[13] as String,
      rate: fields[14] as String,
      refundAddress: fields[15] as String,
      refundExtraId: fields[16] as String?,
      provider: fields[17] as String?,
      providerToken: fields[18] as String?,
      walletId: fields[19] as String?,
      expiresAt: (fields[20] as num?)?.toInt(),
      purchaseSource: fields[21] as String?,
      purchaseFiatUsd: fields[22] as String?,
      operationId: fields[23] as String?,
      routeVersion: fields[24] as String?,
      activityDirection: fields[25] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SwapOrder obj) {
    writer
      ..writeByte(26)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.coinFrom)
      ..writeByte(2)
      ..write(obj.networkFrom)
      ..writeByte(3)
      ..write(obj.coinTo)
      ..writeByte(4)
      ..write(obj.networkTo)
      ..writeByte(5)
      ..write(obj.depositAddress)
      ..writeByte(6)
      ..write(obj.depositExtraId)
      ..writeByte(7)
      ..write(obj.depositAmount)
      ..writeByte(8)
      ..write(obj.withdrawalAmount)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.timestamp)
      ..writeByte(11)
      ..write(obj.withdrawalAddress)
      ..writeByte(12)
      ..write(obj.depositMin)
      ..writeByte(13)
      ..write(obj.depositMax)
      ..writeByte(14)
      ..write(obj.rate)
      ..writeByte(15)
      ..write(obj.refundAddress)
      ..writeByte(16)
      ..write(obj.refundExtraId)
      ..writeByte(17)
      ..write(obj.provider)
      ..writeByte(18)
      ..write(obj.providerToken)
      ..writeByte(19)
      ..write(obj.walletId)
      ..writeByte(20)
      ..write(obj.expiresAt)
      ..writeByte(21)
      ..write(obj.purchaseSource)
      ..writeByte(22)
      ..write(obj.purchaseFiatUsd)
      ..writeByte(23)
      ..write(obj.operationId)
      ..writeByte(24)
      ..write(obj.routeVersion)
      ..writeByte(25)
      ..write(obj.activityDirection);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SwapOrderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
