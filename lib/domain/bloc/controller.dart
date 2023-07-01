import 'dart:io';
import 'package:cached_video_player/cached_video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_editor/domain/entities/file_format.dart';
import 'package:video_editor/domain/helpers.dart';
import 'package:video_editor/domain/thumbnails.dart';
import 'package:path_provider/path_provider.dart';

import 'package:video_editor/domain/entities/crop_style.dart';
import 'package:video_editor/domain/entities/trim_style.dart';
import 'package:video_editor/domain/entities/cover_style.dart';
import 'package:video_editor/domain/entities/cover_data.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoMinDurationError extends Error {
  final Duration minDuration;
  final Duration videoDuration;

  VideoMinDurationError(this.minDuration, this.videoDuration);

  @override
  String toString() =>
      "Invalid argument (minDuration): The minimum duration ($minDuration) cannot be bigger than the duration of the video file ($videoDuration)";
}

enum RotateDirection { left, right }

/// A preset is a collection of options that will provide a certain encoding speed to compression ratio.
///
/// A slower preset will provide better compression (compression is quality per filesize).
///
/// This means that, for example, if you target a certain file size or constant bit rate,
/// you will achieve better quality with a slower preset.
/// Similarly, for constant quality encoding,
/// you will simply save bitrate by choosing a slower preset.
enum VideoExportPreset {
  none,
  ultrafast,
  superfast,
  veryfast,
  faster,
  fast,
  medium,
  slow,
  slower,
  veryslow
}

/// The default value of this property `Offset(1.0, 1.0)`
const Offset _max = Offset(1.0, 1.0);

/// The default value of this property `Offset.zero`
const Offset _min = Offset.zero;

/// Provides an easy way to change edition parameters to apply in the different widgets of the package and at the exportion
/// This controller allows to : rotate, crop, trim, cover generation and exportation (video and cover)
class VideoEditorController extends ChangeNotifier {
  /// Style for [TrimSlider]
  final TrimSliderStyle trimStyle;

  /// Style for [CoverSelection]
  final CoverSelectionStyle coverStyle;

  /// Style for [CropGridViewer]
  final CropGridStyle cropStyle;

  /// Video from [File].
  final File file;

  /// Constructs a [VideoEditorController] that edits a video from a file.
  ///
  /// The [file] argument must not be null.
  VideoEditorController.file(
    this.file, {
    this.maxDuration = Duration.zero,
    this.minDuration = Duration.zero,
    this.coverStyle = const CoverSelectionStyle(),
    this.cropStyle = const CropGridStyle(),
    TrimSliderStyle? trimStyle,
  })  : _video = CachedVideoPlayerController.file(File(
          // https://github.com/flutter/flutter/issues/40429#issuecomment-549746165
          Platform.isIOS ? Uri.encodeFull(file.path) : file.path,
        )),
        trimStyle = trimStyle ?? TrimSliderStyle(),
        assert(maxDuration > minDuration,
            'The maximum duration must be bigger than the minimum duration');

  int _rotation = 0;
  bool _isTrimming = false;
  bool _isTrimmed = false;
  bool isCropping = false;

  double? _preferredCropAspectRatio;

  double _minTrim = _min.dx;
  double _maxTrim = _max.dx;

  Offset _minCrop = _min;
  Offset _maxCrop = _max;

  Offset cacheMinCrop = _min;
  Offset cacheMaxCrop = _max;

  Duration _trimEnd = Duration.zero;
  Duration _trimStart = Duration.zero;
  final CachedVideoPlayerController _video;

  // Selected cover value
  final ValueNotifier<CoverData?> _selectedCover =
      ValueNotifier<CoverData?>(null);

  /// Get the [VideoPlayerController]
  CachedVideoPlayerController get video => _video;

  /// Get the [VideoPlayerController.value.initialized]
  bool get initialized => _video.value.isInitialized;

  /// Get the [VideoPlayerController.value.isPlaying]
  bool get isPlaying => _video.value.isPlaying;

  /// Get the [VideoPlayerController.value.position]
  Duration get videoPosition => _video.value.position;

  /// Get the [VideoPlayerController.value.duration]
  Duration get videoDuration => _video.value.duration;

  /// Get the [VideoPlayerController.value.size]
  Size get videoDimension => _video.value.size;
  double get videoWidth => videoDimension.width;
  double get videoHeight => videoDimension.height;

  /// The [minTrim] param is the minimum position of the trimmed area on the slider
  ///
  /// The minimum value of this param is `0.0`
  /// The maximum value of this param is [maxTrim]
  double get minTrim => _minTrim;

  /// The [maxTrim] param is the maximum position of the trimmed area on the slider
  ///
  /// The minimum value of this param is [minTrim]
  /// The maximum value of this param is `1.0`
  double get maxTrim => _maxTrim;

  /// The [startTrim] param is the maximum position of the trimmed area in video position in [Duration] value
  Duration get startTrim => _trimStart;

  /// The [endTrim] param is the maximum position of the trimmed area in video position in [Duration] value
  Duration get endTrim => _trimEnd;

  /// The [Duration] of the selected trimmed area, it is the difference of [endTrim] and [startTrim]
  Duration get trimmedDuration => endTrim - startTrim;

  /// The [minCrop] param is the [Rect.topLeft] position of the crop area
  ///
  /// The minimum value of this param is `0.0`
  /// The maximum value of this param is `1.0`
  Offset get minCrop => _minCrop;

  /// The [maxCrop] param is the [Rect.bottomRight] position of the crop area
  ///
  /// The minimum value of this param is `0.0`
  /// The maximum value of this param is `1.0`
  Offset get maxCrop => _maxCrop;

  /// Get the [Size] of the [videoDimension] cropped by the points [minCrop] & [maxCrop]
  Size get croppedArea => Rect.fromLTWH(
        0,
        0,
        videoWidth * (maxCrop.dx - minCrop.dx),
        videoHeight * (maxCrop.dy - minCrop.dy),
      ).size;

  /// The [preferredCropAspectRatio] param is the selected aspect ratio (9:16, 3:4, 1:1, ...)
  double? get preferredCropAspectRatio => _preferredCropAspectRatio;
  set preferredCropAspectRatio(double? value) {
    if (preferredCropAspectRatio == value) return;
    _preferredCropAspectRatio = value;
    notifyListeners();
  }

  /// Set [preferredCropAspectRatio] to the current cropped area ratio
  void setPreferredRatioFromCrop() {
    _preferredCropAspectRatio = croppedArea.aspectRatio;
    notifyListeners();
  }

  /// Update the [preferredCropAspectRatio] param and init/reset crop parameters [minCrop] & [maxCrop] to match the desired ratio
  /// The crop area will be at the center of the layout
  void cropAspectRatio(double? value) {
    preferredCropAspectRatio = value;

    if (value != null) {
      final newSize = computeSizeWithRatio(videoDimension, value);

      Rect centerCrop = Rect.fromCenter(
        center: Offset(videoWidth / 2, videoHeight / 2),
        width: newSize.width,
        height: newSize.height,
      );

      _minCrop =
          Offset(centerCrop.left / videoWidth, centerCrop.top / videoHeight);
      _maxCrop = Offset(
          centerCrop.right / videoWidth, centerCrop.bottom / videoHeight);
      notifyListeners();
    }
  }

  //----------------//
  //VIDEO CONTROLLER//
  //----------------//

  /// Attempts to open the given video [File] and load metadata about the video.
  ///
  /// Update the trim position depending on the [maxDuration] param
  /// Generate the default cover [_selectedCover]
  /// Initialize [minCrop] & [maxCrop] values base on [aspectRatio]
  ///
  /// Throw a [VideoMinDurationError] error if the [minDuration] is bigger than [videoDuration], the error should be handled as such:
  /// ```dart
  ///  controller
  ///     .initialize()
  ///     .then((_) => setState(() {}))
  ///     .catchError((error) {
  ///   // NOTE : handle the error here
  /// }, test: (e) => e is VideoMinDurationError);
  /// ```
  Future<void> initialize({double? aspectRatio}) async {
    await _video.initialize();

    if (minDuration > videoDuration) {
      throw VideoMinDurationError(minDuration, videoDuration);
    }

    _video.addListener(_videoListener);
    _video.setLooping(true);

    // if no [maxDuration] param given, maxDuration is the videoDuration
    maxDuration = maxDuration == Duration.zero ? videoDuration : maxDuration;

    // Trim straight away when maxDuration is lower than video duration
    if (maxDuration < videoDuration) {
      updateTrim(
          0.0, maxDuration.inMilliseconds / videoDuration.inMilliseconds);
    } else {
      _updateTrimRange();
    }

    cropAspectRatio(aspectRatio);
    generateDefaultCoverThumbnail();

    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    if (_video.value.isPlaying) await _video.pause();
    _video.removeListener(_videoListener);
    _video.dispose();
    _selectedCover.dispose();
    super.dispose();
  }

  void _videoListener() {
    final position = videoPosition;
    if (position < _trimStart || position > _trimEnd) {
      _video.seekTo(_trimStart);
    }
  }

  //----------//
  //VIDEO CROP//
  //----------//

  /// Convert the [minCrop] and [maxCrop] param in to a [String]
  /// used to provide crop values to Ffmpeg ([see more](https://ffmpeg.org/ffmpeg-filters.html#crop))
  ///
  /// The result is in the format `crop=w:h:x:y`
  String _getCrop() {
    if (minCrop <= _min && maxCrop >= _max) return "";

    final enddx = videoWidth * maxCrop.dx;
    final enddy = videoHeight * maxCrop.dy;
    final startdx = videoWidth * minCrop.dx;
    final startdy = videoHeight * minCrop.dy;

    return "crop=${enddx - startdx}:${enddy - startdy}:$startdx:$startdy";
  }

  /// Update the [minCrop] and [maxCrop] with [cacheMinCrop] and [cacheMaxCrop]
  void applyCacheCrop() => updateCrop(cacheMinCrop, cacheMaxCrop);

  // Update [minCrop] and [maxCrop].
  ///
  /// The [min] param is the [Rect.topLeft] position of the crop area
  /// The [max] param is the [Rect.bottomRight] position of the crop area
  ///
  /// Arguments range are [Offset.zero] to `Offset(1.0, 1.0)`.
  void updateCrop(Offset min, Offset max) {
    assert(min < max,
        'Minimum crop value ($min) cannot be bigger and maximum crop value ($max)');

    _minCrop = min;
    _maxCrop = max;
    notifyListeners();
  }

  //----------//
  //VIDEO TRIM//
  //----------//

  /// Update [minTrim] and [maxTrim].
  ///
  /// The [min] param is the minimum position of the trimmed area on the slider
  /// The [max] param is the maximum position of the trimmed area on the slider
  ///
  /// Arguments range are `0.0` to `1.0`.
  void updateTrim(double min, double max) {
    assert(min < max,
        'Minimum trim value ($min) cannot be bigger and maximum trim value ($max)');

    // check that the new params does not cause a wrong duration
    final newDuration = Duration(
        milliseconds: (videoDuration.inMilliseconds * (max - min)).toInt());
    assert(newDuration <= maxDuration && newDuration >= minDuration,
        'Trim duration ($newDuration) cannot be bigger than $maxDuration or smaller than $minDuration');

    _minTrim = min;
    _maxTrim = max;
    _updateTrimRange();
  }

  void _updateTrimRange() {
    _trimStart = videoDuration * minTrim;
    _trimEnd = videoDuration * maxTrim;

    if (_trimStart != Duration.zero || _trimEnd != videoDuration) {
      _isTrimmed = true;
    } else {
      _isTrimmed = false;
    }

    _checkUpdateDefaultCover();

    notifyListeners();
  }

  /// Get the [isTrimmed]
  ///
  /// `true` if the trimmed value has beem changed
  bool get isTrimmed => _isTrimmed;

  /// Get the [isTrimming]
  ///
  /// `true` if the trimming values are curently getting updated
  bool get isTrimming => _isTrimming;
  set isTrimming(bool value) {
    _isTrimming = value;
    if (!value) {
      _checkUpdateDefaultCover();
    }
    notifyListeners();
  }

  /// Get the [maxDuration] param
  ///
  /// if no [maxDuration] param given in VideoEditorController constructor, maxDuration is equals to the videoDuration
  Duration maxDuration;

  /// Get the [minDuration] param
  ///
  /// if no [minDuration] param given in VideoEditorController constructor, minDuration is equals to [Duration.zero]
  /// throw a [VideoMinDurationError] error at initialization if the [minDuration] is bigger then [videoDuration]
  Duration minDuration;

  /// Get the [trimPosition], which is the videoPosition in the trim slider
  ///
  /// Range of the param is `0.0` to `1.0`.
  double get trimPosition =>
      videoPosition.inMilliseconds / videoDuration.inMilliseconds;

  //-----------//
  //VIDEO COVER//
  //-----------//

  /// Replace selected cover by [selectedCover]
  void updateSelectedCover(CoverData selectedCover) async {
    _selectedCover.value = selectedCover;
  }

  /// Init selected cover value at initialization or after trimming change
  ///
  /// If [isTrimming] is `false` or  [_selectedCover] is `null`, update _selectedCover
  /// Update only milliseconds time for performance reason
  void _checkUpdateDefaultCover() {
    if (!_isTrimming || _selectedCover.value == null) {
      updateSelectedCover(CoverData(timeMs: startTrim.inMilliseconds));
    }
  }

  /// Generate cover at [startTrim] time in milliseconds
  void generateDefaultCoverThumbnail() async {
    final defaultCover = await generateSingleCoverThumbnail(
      file.path,
      timeMs: startTrim.inMilliseconds,
    );
    updateSelectedCover(defaultCover);
  }

  /// Get the [selectedCover] notifier
  ValueNotifier<CoverData?> get selectedCoverNotifier => _selectedCover;

  /// Get the [selectedCover] value
  CoverData? get selectedCoverVal => _selectedCover.value;

  //------------//
  //VIDEO ROTATE//
  //------------//

  /// Get the rotation of the video, value should be a multiple of `90`
  int get cacheRotation => _rotation;

  /// Get the rotation of the video,
  /// possible values are: `0`, `90`, `180` and `270`
  int get rotation => (_rotation ~/ 90 % 4) * 90;

  /// Rotate the video by 90 degrees in the [direction] provided
  void rotate90Degrees([RotateDirection direction = RotateDirection.right]) {
    switch (direction) {
      case RotateDirection.left:
        _rotation += 90;
        break;
      case RotateDirection.right:
        _rotation -= 90;
        break;
    }
    notifyListeners();
  }

  bool get isRotated => rotation == 90 || rotation == 270;

  /// Convert the [rotation] value into a [String]
  /// used to provide crop values to Ffmpeg ([see more](https://ffmpeg.org/ffmpeg-filters.html#transpose-1))
  ///
  /// The result is in the format `transpose=2` (repeated for every 90 degrees rotations)
  String _getRotation() {
    final count = rotation / 90;
    if (count <= 0 || count >= 4) return "";

    List<String> transpose = [];
    for (int i = 0; i < rotation / 90; i++) {
      transpose.add("transpose=2");
    }
    return transpose.isNotEmpty ? transpose.join(',') : "";
  }

  //--------//
  // EXPORT //
  //--------//

  /// Returns the output path of the exported file
  Future<String> _getOutputPath({
    required String filePath,
    String? name,
    String? outputDirectory,
    required FileFormat format,
  }) async {
    final String tempPath =
        outputDirectory ?? (await getTemporaryDirectory()).path;
    name ??= path.basenameWithoutExtension(filePath);
    final int epoch = DateTime.now().millisecondsSinceEpoch;
    return "$tempPath/${name}_$epoch.${format.extension}";
  }


  Future<void> exportVideo({
    required void Function(File file) onCompleted,
    void Function(Object, StackTrace)? onError,
    VideoQuality quality = VideoQuality.Res1280x720Quality,
    void Function(double)? onProgress,
  }) async {
    final String videoPath = file.path;
    final String outputPath = await _getOutputPath(
      filePath: videoPath,
      format: VideoExportFormat.mp4,
    );

    final Subscription subscription =
        VideoCompress.compressProgress$.subscribe((progress) {
      if (onProgress != null) {
        onProgress(progress);
      }
      debugPrint('progress: $progress');
    });

    debugPrint('Starttime: ${startTrim.inMilliseconds}');
    debugPrint('Duration: ${(endTrim-startTrim).inMilliseconds}');

    final compressedFile = await VideoCompress.compressVideo(
      videoPath,
      quality: quality,
      deleteOrigin: false,
      includeAudio: true,
      startTime: startTrim.inMilliseconds,
      duration: (endTrim-startTrim).inMilliseconds,
    );

    subscription.unsubscribe();

    if (compressedFile != null) {
      final File compressedFileP = File(compressedFile.path!);

      if (await compressedFileP.exists()) {
        final Directory outputDir = Directory(path.dirname(outputPath));
        if (!await outputDir.exists()) {
          await outputDir.create(recursive: true);
        }

        await compressedFileP.copy(outputPath);
        onCompleted(File(outputPath));
      } else {
        if (onError != null) {
          onError(Exception('Failed to compress video'), StackTrace.current);
        }
      }
    } else {
      if (onError != null) {
        onError(Exception('Failed to compress video'), StackTrace.current);
      }
    }
  }

  /// Generate this selected cover image as a JPEG [File]
  ///
  /// If this [selectedCoverVal] is `null`, then it return the first frame of this video.
  ///
  /// The [quality] param specifies the quality of the generated cover, from 0 to 100 (([more info](https://pub.dev/packages/video_thumbnail)))
  Future<String?> _generateCoverFile({int quality = 100}) async {
    return await VideoThumbnail.thumbnailFile(
      imageFormat: ImageFormat.JPEG,
      thumbnailPath: (await getTemporaryDirectory()).path,
      video: file.path,
      timeMs: selectedCoverVal?.timeMs ?? startTrim.inMilliseconds,
      quality: quality,
    );
  }

  /// Export this selected cover, or by default the first one, return an image [File].
  ///
  /// The [onCompleted] param must be set to return the exported [File] cover
  ///
  /// The [onError] function provides the [Exception] and [StackTrace] that causes the exportation error.
  ///
  /// If the [name] is `null`, then it uses this video filename.
  ///
  /// If the [outDir] is `null`, then it uses `TemporaryDirectory`.
  ///
  /// The [format] of the image to be exported, by default [CoverExportFormat.jpg].
  ///
  /// The [scale] is `scale=width*scale:height*scale` and reduce or increase cover size.
  ///
  /// The [quality] of the exported image (from 0 to 100 ([more info](https://pub.dev/packages/video_thumbnail)))
  ///
  /// The [onProgress] is called while the video is exporting.
  /// This argument is usually used to update the export progress percentage.
  /// This function return [Statistics] from FFmpeg session.
  ///
  /// Set [isFiltersEnabled] to `false` if you do not want to apply any changes
  Future<void> extractCover({
    required void Function(File file) onCompleted,
    void Function(Object, StackTrace)? onError,
    String? name,
    String? outDir,
    int quality = 100,
    void Function(double)? onProgress,
  }) async {
    final String? coverPath = await _generateCoverFile(quality: quality);
    if (coverPath == null) {
      if (onError != null) {
        onError(
          Exception('VideoThumbnail library error while exporting the cover'),
          StackTrace.current,
        );
      }
      return;
    }

    final String outputPath = await _getOutputPath(
      filePath: coverPath,
      name: name,
      outputDirectory: outDir,
      format: CoverExportFormat.jpeg,
    );

    final Uint8List? thumbnailBytes = await VideoThumbnail.thumbnailData(
      video: coverPath,
      imageFormat: ImageFormat.JPEG,
      quality: quality,
      maxWidth: 1080,
      maxHeight: 1920,
    );

    if (thumbnailBytes != null) {
      final File thumbnailFile = File(outputPath);
      await thumbnailFile.writeAsBytes(thumbnailBytes);
      onCompleted(thumbnailFile);
    } else {
      if (onError != null) {
        onError(
            Exception('Failed to extract cover thumbnail'), StackTrace.current);
      }
    }
  }
}
