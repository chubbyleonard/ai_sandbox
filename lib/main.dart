import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF007AFF),
          surface: Color(0xFF1A1A24),
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

class _ChatScreenState extends State<ChatScreen> {
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
    if (prompt.isEmpty || _isGenerating) return;

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
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Network Routing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ipController,
          decoration: const InputDecoration(
            labelText: 'Tailscale / Server IP',
            hintText: '100.78.140.104',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
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
        title: const Text(
          'Private Brain',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.3),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF14141B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.grey),
            onPressed: _openNetworkSettings,
            tooltip: 'Network Routing',
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF14141B),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.history, color: Color(0xFF007AFF), size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Chat History',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Text(
                          'No saved prompts yet.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _messages.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          if (msg['role'] != 'user') return const SizedBox.shrink();

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                            leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF007AFF), size: 18),
                            title: Text(
                              msg['output'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _scrollToBottom();
                            },
                          );
                        },
                      ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.12),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  label: const Text('Wipe Local Database', style: TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: () {
                    _clearHistory();
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1E1E28),
                          ),
                          child: Icon(Icons.psychology_outlined, size: 48, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Unrestricted Local Engine Ready',
                          style: TextStyle(color: Colors.grey[400], fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['role'] == 'user';

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              gradient: isUser
                                  ? const LinearGradient(
                                      colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: isUser ? null : const Color(0xFF1E1E28),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(isUser ? 18 : 4),
                                bottomRight: Radius.circular(isUser ? 4 : 18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: isUser
                                ? Text(
                                    msg['output'] ?? '',
                                    style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (msg['thinking'] != null && msg['thinking'].isNotEmpty)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.black38,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.white10),
                                          ),
                                          child: Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                                              title: const Text(
                                                'Thinking Process...',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 13,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                                                  child: Text(
                                                    msg['thinking'],
                                                    style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 13,
                                                      fontStyle: FontStyle.italic,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (msg['output'] != null && msg['output'].isNotEmpty) ...[
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
                                        ),
                                        const SizedBox(height: 6),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(6),
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(text: msg['output'] ?? ''));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Copied to clipboard'),
                                                  duration: Duration(seconds: 1),
                                                ),
                                              );
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(4.0),
                                              child: Icon(Icons.copy_outlined, size: 16, color: Colors.grey),
                                            ),
                                          ),
                                        ),
                                      ] else if (_isGenerating && index == _messages.length - 1)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF007AFF)),
                                            ),
                                            SizedBox(width: 10),
                                            Text('Thinking...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                          ],
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF14141B),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF20202C),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: const TextStyle(fontSize: 15),
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
                    backgroundColor: const Color(0xFF007AFF),
                    radius: 20,
                    child: IconButton(
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
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