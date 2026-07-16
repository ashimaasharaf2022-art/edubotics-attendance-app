class LeaveConstants {
  static const String casual = "casual";
  static const String medical = "medical";

  static const List<String> allTypes = [casual, medical];

  static const Map<String, int> defaultQuota = {
    casual: 15,
    medical: 5,
  };

  static String displayName(String type) {
    switch (type) {
      case casual:
        return "Casual Leave";
      case medical:
        return "Medical Leave";
      default:
        return type;
    }
  }
}

enum LeaveStatus { pending, approved, rejected }

LeaveStatus leaveStatusFromString(String? value) {
  switch (value) {
    case "approved":
      return LeaveStatus.approved;
    case "rejected":
      return LeaveStatus.rejected;
    default:
      return LeaveStatus.pending;
  }
}

String leaveStatusToString(LeaveStatus status) {
  switch (status) {
    case LeaveStatus.approved:
      return "approved";
    case LeaveStatus.rejected:
      return "rejected";
    case LeaveStatus.pending:
      return "pending";
  }
}