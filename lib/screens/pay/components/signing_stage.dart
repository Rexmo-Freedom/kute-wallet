// lib/screens/pay/components/signing_stage.dart
//
// Presentation vocabulary for the Sign step of a hardware / watch-only
// send. Pure visuals: nothing here decides anything, it only draws what
// `watch_only_screen.dart` is already doing.
//
// The house pattern this follows is the Ledger approval sheet
// (`lib/screens/ledger/ledger_connect_steps.dart`): one glyph, one title,
// one sentence, and the buttons for whatever comes next. The signing
// screen used to stack numbered instruction rows inside expandable cards;
// these widgets replace that with a single calm stage so only one thing
// is happening on screen at a time.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:kute/theme/app_theme.dart';

/// How a [SigningStage] reads: something is running, something finished,
/// or something went wrong.
enum SigningStageTone { working, done, problem }

/// Spinner (or a still glyph under reduce motion), title, one sentence,
/// then the actions. The whole signing screen speaks through this.
class SigningStage extends StatelessWidget {
  const SigningStage({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.body,
    this.actions = const <Widget>[],
  });

  final SigningStageTone tone;

  /// Drawn when the stage is not spinning, and whenever the OS asks for
  /// reduced motion.
  final IconData icon;
  final String title;
  final String? body;

  /// Stacked full width under the copy, first one is the primary.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final spinning = tone == SigningStageTone.working && !reduceMotion;
    final glyphColor = switch (tone) {
      SigningStageTone.done => c.success,
      SigningStageTone.problem => c.error,
      SigningStageTone.working => c.textSecondary,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56.h,
          child: Center(
            child: spinning
                ? LoadingAnimationWidget.staggeredDotsWave(
                    color: glyphColor, size: 32.sp)
                : ExcludeSemantics(
                    child: Icon(icon, size: 34.sp, color: glyphColor)),
          ),
        ),
        SizedBox(height: 4.h),
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.heading3(context),
          ),
        ),
        if (body != null) ...[
          SizedBox(height: 8.h),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 15.sp,
              height: 1.4,
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          SizedBox(height: 20.h),
          for (int i = 0; i < actions.length; i++) ...[
            if (i > 0) SizedBox(height: 10.h),
            actions[i],
          ],
        ],
      ],
    );
  }
}

/// What the user is approving, kept on screen the whole way through so
/// the amount and the destination are never out of sight.
///
/// The address is printed in full and never shortened: the point of the
/// row is that the user compares it character for character with the
/// screen on the device.
class SigningSummaryCard extends StatelessWidget {
  const SigningSummaryCard({
    super.key,
    required this.amount,
    required this.addressLabel,
    required this.address,
    required this.note,
    this.feeLabel,
    this.fee,
  });

  final String amount;
  final String addressLabel;
  final String address;

  /// The plain sentence asking the user to compare with the device.
  final String note;
  final String? feeLabel;
  final String? fee;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 16.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            amount,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 28.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: 14.h),
          _line(context, addressLabel, address, monospace: true),
          if (fee != null && feeLabel != null) ...[
            SizedBox(height: 10.h),
            _line(context, feeLabel!, fee!),
          ],
          SizedBox(height: 14.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(Icons.visibility_outlined,
                    size: 16.sp, color: c.textTertiary),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  note,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value,
      {bool monospace = false}) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 3.h),
        Text(
          value,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: monospace ? 14.sp : 15.sp,
            fontWeight: FontWeight.w600,
            height: 1.35,
            letterSpacing: monospace ? 0 : -0.1,
            fontFamily: monospace ? 'monospace' : null,
          ),
        ),
      ],
    );
  }
}

/// One quiet sentence above an action. Replaces the numbered instruction
/// rows the signing methods used to stack on top of each other.
class SigningHint extends StatelessWidget {
  const SigningHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Text(
        text,
        style: TextStyle(color: c.textSecondary, fontSize: 14.sp, height: 1.4),
      ),
    );
  }
}

/// The device this payment is being signed on, sitting above its panel.
class SigningDeviceRow extends StatelessWidget {
  const SigningDeviceRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leading,
  });

  final String title;
  final String subtitle;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        leading,
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 1.h),
              Text(
                subtitle,
                style: TextStyle(color: c.textSecondary, fontSize: 13.sp),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The surface every signing panel sits on, so the flagship Bluetooth
/// panel and the fallbacks read as the same object.
class SigningPanel extends StatelessWidget {
  const SigningPanel({super.key, required this.child, this.header});

  final Widget child;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[
            header!,
            SizedBox(height: 14.h),
            Divider(color: c.borderSubtle, height: 1),
            SizedBox(height: 14.h),
          ],
          child,
        ],
      ),
    );
  }
}
