import 'package:flutter/material.dart';

/// Keeps amount entry pinned while a ticket is quiet. A message gives the
/// upper form that space back: the same input scrolls after the message,
/// so it stays editable without squeezing the explanation behind it.
/// The scroll position stays mounted; there is no automatic scroll jump.
class SlipFormBody extends StatelessWidget {
  const SlipFormBody({
    super.key,
    required this.form,
    required this.input,
    required this.expandForMessage,
  });

  final Widget form;
  final Widget input;
  final bool expandForMessage;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [form, if (expandForMessage) input],
              ),
            ),
          ),
          if (!expandForMessage) input,
        ],
      );
}
