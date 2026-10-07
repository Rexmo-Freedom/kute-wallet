import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:qr_flutter/qr_flutter.dart';

Widget buildQrCode(String address, BuildContext context) {
  return Container(
    decoration: const BoxDecoration(
      color: Colors.white,
    ),
    child: Hero(
      tag: 'qrCode_$address',
      child: QrImageView(
        data: address,
        version: QrVersions.auto,
        size: 0.5.sw,
        // Quiet-zone padding around the modules. Was 3, which let
        // the outer 14r ClipRRect (`_RevealSheet`, receive sheet)
        // cut INTO the eye-finder squares on low-version QRs (e.g.
        // a 12-word mnemonic). With short data the QR uses few,
        // large modules and the eye-finders sit close to the edge;
        // a 3px buffer wasn't enough to keep them clear of a 14dp
        // corner radius. 16px gives every QR the same standard
        // quiet zone so the corners look identical regardless of
        // how much data the code carries.
        padding: const EdgeInsets.all(16),
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.circle,
          color: Colors.black,
        ),
      ),
    ),
  );
}