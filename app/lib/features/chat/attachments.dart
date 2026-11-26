import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

/// Thumbnails; tap opens the image full screen (or the PDF in the phone's viewer). Links are signed on demand.
class AttachmentStrip extends ConsumerWidget {
  const AttachmentStrip({super.key, required this.attachments});
  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: attachments.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => _Thumb(a: attachments[i]),
        ),
      );
}

final _urlProvider = FutureProvider.family<String, String>((ref, key) => ref.watch(repositoryProvider).fileUrl(key));

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.a});
  final Attachment a;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(_urlProvider(a.key)).value;
    final c = Theme.of(context).colorScheme;
    return InkWell(
      onTap: url == null ? null : () {
        if (a.isImage) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(
                appBar: AppBar(),
                backgroundColor: Colors.black,
                body: Center(child: InteractiveViewer(child: Image.network(url))),
              )));
        } else {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 72, height: 72, color: c.surfaceContainerHighest,
          child: a.isImage && url != null ? Image.network(url, fit: BoxFit.cover) : Icon(a.isImage ? Icons.image : Icons.picture_as_pdf, color: c.onSurfaceVariant),
        ),
      ),
    );
  }
}
