import 'package:dio/dio.dart';
import '../models/chat_message.dart';

/// Response DTO from POST /chat.
class ChatApiResponse {
  const ChatApiResponse({
    required this.assistantMessage,
    this.calendarEvent,
  });
  final String assistantMessage;
  final CalendarEvent? calendarEvent;
}

/// Stateless API client. Business logic lives in ChatController.
class ChatApiService {
  ChatApiService({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

  final Dio _dio;

  /// POST /chat. Throws DioException on network/server error.
  Future<ChatApiResponse> sendMessage({
    required String sessionId,
    required String message,
    required CancelToken cancelToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat',
      data: {'session_id': sessionId, 'message': message},
      cancelToken: cancelToken,
    );

    final data = response.data!;
    final rawEvent = data['calendar_event'];

    return ChatApiResponse(
      assistantMessage: data['assistant_message'] as String,
      calendarEvent: rawEvent != null
          ? CalendarEvent.fromJson(rawEvent as Map<String, dynamic>)
          : null,
    );
  }
}
