import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/models/image.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_scope.dart';
import 'package:interstellar/src/widgets/avatar.dart';
import 'package:provider/provider.dart';

class DisplayName extends StatelessWidget {
  const DisplayName(
    this.name, {
    super.key,
    this.displayName,
    this.icon,
    this.onTap,
  });

  final String name;
  final String? displayName;
  final ImageModel? icon;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final nameTuple = name.split('@');
    final localName = displayName ?? nameTuple.first;
    final hostName = nameTuple.length > 1 ? nameTuple[1] : null;

    final ac = context.watch<AppController>();
    // Merged views mix servers, so names there always carry theirs, and a
    // bare name belongs to the account whose copy is shown.
    final scope = AccountScope.maybeOf(context);
    final alwaysShow = ac.profile.alwaysShowInstance || scope != null;
    final instance = instanceToShow(
      name,
      alwaysShow: alwaysShow,
      viewerHost: scope?.account.split('@').last ?? ac.instanceHost,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Avatar(icon, radius: 14),
          ),
        Flexible(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              // the bare "@" below sits right against the name
              padding: EdgeInsets.fromLTRB(
                3,
                3,
                !alwaysShow && hostName != null ? 0 : 3,
                3,
              ),
              child: Text(
                instance == null ? localName : '$localName@$instance',
                style: Theme.of(context).textTheme.labelLarge,
                softWrap: false,
                overflow: TextOverflow.fade,
              ),
            ),
          ),
        ),
        if (!alwaysShow && hostName != null)
          Tooltip(
            message: hostName,
            triggerMode: TooltipTriggerMode.tap,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(0, 3, 3, 3),
              child: Text('@'),
            ),
          ),
      ],
    );
  }
}
