import 'package:equatable/equatable.dart';

sealed class MediaEvent extends Equatable {
  const MediaEvent();

  @override
  List<Object?> get props => const [];
}

class ResolveRequested extends MediaEvent {
  const ResolveRequested(this.url);

  final String url;

  @override
  List<Object?> get props => [url];
}

class SelectionToggled extends MediaEvent {
  const SelectionToggled(this.itemId);

  final String itemId;

  @override
  List<Object?> get props => [itemId];
}

class SelectionSet extends MediaEvent {
  const SelectionSet(this.selectAll);

  final bool selectAll;

  @override
  List<Object?> get props => [selectAll];
}

class VariantChosen extends MediaEvent {
  const VariantChosen({required this.itemId, required this.variantId});

  final String itemId;
  final String variantId;

  @override
  List<Object?> get props => [itemId, variantId];
}

class DownloadRequested extends MediaEvent {
  const DownloadRequested();
}

class DownloadCancelled extends MediaEvent {
  const DownloadCancelled();
}

class NoticeRequested extends MediaEvent {
  const NoticeRequested(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class VariantMeasured extends MediaEvent {
  const VariantMeasured({
    required this.sourceUrl,
    required this.itemId,
    required this.variantId,
    required this.bytes,
  });

  final String sourceUrl;
  final String itemId;
  final String variantId;
  final int bytes;

  @override
  List<Object?> get props => [sourceUrl, itemId, variantId, bytes];
}
