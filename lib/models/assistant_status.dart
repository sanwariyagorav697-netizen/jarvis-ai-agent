/// Assistant ke state machine ke statuses. UI inhi par animation/audio lock banata hai.
enum AssistantStatus { idle, listening, thinking, speaking, success, error }

extension AssistantStatusLabel on AssistantStatus {
  /// UI me dikhane wala chhota label (English, ALL CAPS style JARVIS HUD ke liye).
  String get shortLabel => switch (this) {
        AssistantStatus.idle => 'STANDBY',
        AssistantStatus.listening => 'LISTENING',
        AssistantStatus.thinking => 'PROCESSING',
        AssistantStatus.speaking => 'SPEAKING',
        AssistantStatus.success => 'DONE',
        AssistantStatus.error => 'FAULT',
      };

  /// User ko error/limit samjhaane ke liye Hindi line.
  String get hindiHint => switch (this) {
        AssistantStatus.idle => 'मैं तैयार हूँ। माइक दबाकर बोलिए।',
        AssistantStatus.listening => 'सुन रहा हूँ…',
        AssistantStatus.thinking => 'सोच रहा हूँ…',
        AssistantStatus.speaking => 'बोल रहा हूँ…',
        AssistantStatus.success => 'काम पूरा हुआ।',
        AssistantStatus.error => 'कुछ गड़बड़ हुई — नीचे देखिए।',
      };

  bool get isBusy =>
      this == AssistantStatus.listening ||
      this == AssistantStatus.thinking ||
      this == AssistantStatus.speaking;
}
