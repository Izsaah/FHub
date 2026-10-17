import 'package:flutter/material.dart';
import '../models/check_in_feed_model.dart';
import '../services/family_state_manager.dart';

class CheckInFeedView extends StatelessWidget {
  final String? familyId;

  const CheckInFeedView({super.key, this.familyId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CheckInFeedModel>>(
      future: FamilyStateManager().service.getCheckInFeeds(familyId: familyId),
      builder: (context, snapshot) {
        final feeds = snapshot.data ?? [];
        if (feeds.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 18, color: Color(0xFF005F50)),
                  SizedBox(width: 8),
                  Text(
                    'Khoảnh khắc Check-in hôm nay',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF151D1B),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: feeds.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final feed = feeds[index];
                  final timeStr =
                      '${feed.createdAt.hour.toString().padLeft(2, '0')}:${feed.createdAt.minute.toString().padLeft(2, '0')}';
                  return Container(
                    width: 220,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFBDC9C4).withValues(alpha: 0.5),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0C000000),
                          offset: Offset(0, 4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (feed.imageUrl != null)
                          Image.network(
                            feed.imageUrl!,
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 100,
                              color: const Color(0xFFEDF5F2),
                              child: const Icon(Icons.image,
                                  color: Color(0xFF005F50)),
                            ),
                          )
                        else
                          Container(
                            height: 60,
                            color: const Color(0xFFEDF5F2),
                            alignment: Alignment.center,
                            child: const Icon(Icons.favorite,
                                color: Color(0xFF005F50)),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    feed.userName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF005F50),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    timeStr,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              if (feed.caption != null &&
                                  feed.caption!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  feed.caption!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF2B3633),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
