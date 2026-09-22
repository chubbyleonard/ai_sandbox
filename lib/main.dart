import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ai_service.dart';
import 'db_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UnrestrictedAIApp());
}

class UnrestrictedAIApp extends StatelessWidget {
  const UnrestrictedAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Private Brain',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AIService _aiService = AIService();
  
  final List<Map<String, dynamic>> _messages = [];
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (kIsWeb) return;
    try {
      final history = await DatabaseHelper.instance.fetchMessages();
      setState(() {
        _messages.addAll(history.map((e) => Map<String, dynamic>.from(e)).toList());
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  Future<void> _clearHistory() async {
    if (!kIsWeb) {
      await DatabaseHelper.instance.clearHistory();
    }
    setState(() {
      _messages.clear();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final prompt = _textController.text.trim();
    if (prompt.isEmpty) return;

    if (!kIsWeb) {
      await DatabaseHelper.instance.saveMessage('user', prompt, '');
    }

    setState(() {
      _messages.add({'role': 'user', 'output': prompt, 'thinking': ''});
      _messages.add({'role': 'ai', 'output': '', 'thinking': ''});
      _isGenerating = true;
    });
    
    _textController.clear();
    _scrollToBottom();
    final aiMessageIndex = _messages.length - 1;

    String finalOutput = '';
    String finalThinking = '';

    try {
      await for (var chunk in _aiService.streamPrompt(prompt)) {
        setState(() {
          _messages[aiMessageIndex]['thinking'] = chunk['thinking'] ?? '';
          _messages[aiMessageIndex]['output'] = chunk['output'] ?? '';
        });
        finalThinking = chunk['thinking'] ?? '';
        finalOutput = chunk['output'] ?? '';
        _scrollToBottom();
      }
    } catch (e) {
      finalOutput = "Error communicating with local server: $e";
      setState(() {
        _messages[aiMessageIndex]['output'] = finalOutput;
      });
    }

    if (!kIsWeb) {
      await DatabaseHelper.instance.saveMessage('ai', finalOutput, finalThinking);
    }

    setState(() {
      _isGenerating = false;
    });
    _scrollToBottom();
  }

  void _openNetworkSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final currentIp = prefs.getString('server_ip') ?? '100.78.140.104'; 
    final ipController = TextEditingController(text: currentIp);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Network Routing'),
        content: TextField(
          controller: ipController,
          decoration: const InputDecoration(
            labelText: 'Tailscale Server IP',
            hintText: '100.x.y.z',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              await prefs.setString('server_ip', ipController.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save Routing'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Brain', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF181818),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            onPressed: _clearHistory,
            tooltip: 'Clear History',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.grey),
            onPressed: _openNetworkSettings,
            tooltip: 'Settings',
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.psychology_outlined, size: 64, color: Colors.grey[800]),
                        const SizedBox(height: 16),
                        Text(
                          'Unrestricted Local AI Ready',
                          style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['role'] == 'user';

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF0056D2) : const Color(0xFF1E1E2C),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 16),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: isUser
                              ? Text(msg['output'] ?? '', style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4))
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (msg['thinking'] != null && msg['thinking'].isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                                          title: const Text('Thinking Process...', style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic)),
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Text(msg['thinking'], style: const TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (msg['output'] != null && msg['output'].isNotEmpty)
                                      MarkdownBody(
                                        data: msg['output'],
                                        selectable: true,
                                        onTapLink: (text, href, title) async {
                                          if (href != null) {
                                            final url = Uri.parse(href);
                                            if (await canLaunchUrl(url)) {
                                              await launchUrl(url, mode: LaunchMode.externalApplication);
                                            }
                                          }
                                        },
                                        styleSheet: MarkdownStyleSheet(
                                          p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                                          code: const TextStyle(backgroundColor: Colors.black45, fontFamily: 'Courier', fontSize: 13),
                                          codeblockDecoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      )
                                    else if (_isGenerating && index == _messages.length - 1)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('Thinking...', style: TextStyle(color: Colors.grey, fontSize: 14)),
                                        ],
                                      ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF181818),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey[850]!),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Message Private Brain...',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    radius: 22,
                    child: IconButton(
                      icon: _isGenerating 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                      onPressed: _isGenerating ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}