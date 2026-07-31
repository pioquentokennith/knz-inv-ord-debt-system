// ─────────────────────────────────────────────────────────────────────────────
// reseller_screen.dart — Manage resellers (add / edit / delete)
// Purpose : Lists all resellers for the current user with their discount
//           percentage. FAB opens ResellerDialog to add; tapping a row edits.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/reseller_model.dart';
import '../dialogs/reseller_dialog.dart';
import '../widgets/shared_widgets.dart';

class ResellersScreen extends StatelessWidget {
  const ResellersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState(),
      builder: (context, _) {
        final resellers = AppState().resellers;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                Expanded(
                  child: resellers.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: resellers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) =>
                              _ResellerCard(reseller: resellers[i]),
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add),
            label: const Text(
              'Add Reseller',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const ResellerDialog(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 16),
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: const Row(
        children: [
          Icon(Icons.people_outline, color: AppColors.gold, size: 24),
          SizedBox(width: 10),
          Text(
            'Resellers',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, color: AppColors.whiteTertiary, size: 56),
          SizedBox(height: 12),
          Text(
            'No resellers yet',
            style: TextStyle(color: AppColors.whiteSecondary, fontSize: 16),
          ),
          SizedBox(height: 4),
          Text(
            'Tap + to add your first reseller',
            style: TextStyle(color: AppColors.whiteTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ResellerCard extends StatelessWidget {
  final Reseller reseller;
  const _ResellerCard({required this.reseller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.gold.withValues(alpha: 0.15),
          child: Text(
            reseller.name[0].toUpperCase(),
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          reseller.name,
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: reseller.contact != null
            ? Text(
                reseller.contact!,
                style: const TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 12,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                '−₱${reseller.deductionPerItem.toStringAsFixed(0)}/item',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              color: AppColors.surfaceElevated,
              icon: const Icon(Icons.more_vert, color: AppColors.whiteTertiary),
              onSelected: (action) async {
                if (action == 'edit') {
                  showDialog(
                    context: context,
                    builder: (_) => ResellerDialog(existing: reseller),
                  );
                } else if (action == 'delete') {
                  final confirm = await showConfirmDialog(
                    context,
                    title: 'Delete Reseller',
                    message:
                        'Remove ${reseller.name} from resellers? This cannot be undone.',
                    confirmLabel: 'Delete',
                    confirmColor: AppColors.error,
                    icon: Icons.person_remove_rounded,
                  );
                  if (confirm && context.mounted) {
                    try {
                      await AppState().deleteReseller(reseller.id);
                      if (context.mounted) {
                        KnzToast.info(
                          context,
                          '${reseller.name} removed from resellers.',
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        KnzToast.error(
                          context,
                          'The reseller could not be deleted. Please try again.',
                        );
                      }
                    }
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        color: AppColors.whiteSecondary,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Edit',
                        style: TextStyle(color: AppColors.whiteSecondary),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: AppColors.error,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
