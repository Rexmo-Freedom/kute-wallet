// lib/screens/polymarket/components/market_comments.dart
//
// What people wrote under a Polymarket event (Gamma comments), newest
// first: the "News" section of the market's Rules and resolution sheet.
// Read once, when the section is first built.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/theme/app_theme.dart';

class PolyMarketComments extends StatefulWidget {
  final int eventId;
  const PolyMarketComments({super.key, required this.eventId});

  @override
  State<PolyMarketComments> createState() => _PolyMarketCommentsState();
}

class _PolyMarketCommentsState extends State<PolyMarketComments> {
  List<Comment>? _comments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = PolymarketModel();
    try {
      final comments = await model.getEventComments(widget.eventId, limit: 30);
      if (mounted) setState(() => _comments = comments);
    } catch (_) {
      if (mounted) setState(() => _comments = const []);
    } finally {
      model.dispose();
    }
  }

  @override
  Widget build(BuildContext context) =>
      _NewsTab(comments: _comments, isLoading: _comments == null);
}

class _NewsTab extends StatelessWidget {
  final List<Comment>? comments;
  final bool isLoading;

  const _NewsTab({
    required this.comments,
    required this.isLoading,
  });

  static String _timeAgo(BuildContext context, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return context.l10n.predictJustNow;
    if (diff.inMinutes < 60) {
      return context.l10n.predictMinutesAgoShort('${diff.inMinutes}');
    }
    if (diff.inHours < 24) {
      return context.l10n.predictHoursAgoShort('${diff.inHours}');
    }
    if (diff.inDays < 7) {
      return context.l10n.predictDaysAgoShort('${diff.inDays}');
    }
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (isLoading) {
      // Skeleton mimicking the comment rows about to appear.
      return KuteSkeleton(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonCircle(28.w),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBar(90.w, 11.h),
                          SizedBox(height: 6.h),
                          SkeletonBar(double.infinity, 12.h),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    if (comments == null || comments!.isEmpty) {
      return SizedBox(
        height: 80.h,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 14.sp, color: c.textTertiary),
              SizedBox(width: 6.w),
              Text(
                context.l10n.predictNoCommentsYet,
                style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < comments!.length && i < 10; i++) ...[
          _CommentRow(comment: comments![i]),
          if (i < comments!.length - 1 && i < 9)
            Divider(
                color: c.border.withValues(alpha: 0.3),
                height: 1),
        ],
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  final Comment comment;
  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = comment.profile?.name ??
        comment.profile?.pseudonym ??
        (comment.userAddress != null && comment.userAddress!.length >= 10
            ? '${comment.userAddress!.substring(0, 6)}...${comment.userAddress!.substring(comment.userAddress!.length - 4)}'
            : context.l10n.predictAnonymousUser);
    final body = comment.body ?? '';
    final timeStr = comment.createdAt != null
        ? _NewsTab._timeAgo(context, comment.createdAt!)
        : '';
    final likes = comment.reactionCount ?? 0;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
                Container(
                width: 22.w,
                height: 22.w,
                decoration: BoxDecoration(
                  color: HSLColor.fromAHSL(
                          1.0, (name.hashCode % 360).toDouble(), 0.5, 0.45)
                      .toColor(),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                name,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 6.w),
              Text(
                timeStr,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 12.sp,
                ),
              ),
              const Spacer(),
              if (likes > 0) ...[
                Icon(Icons.thumb_up_outlined,
                    size: 11.sp, color: c.textTertiary),
                SizedBox(width: 3.w),
                Text(
                  '$likes',
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 4.h),
          Padding(
            padding: EdgeInsets.only(left: 30.w),
            child: Text(
              body,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
