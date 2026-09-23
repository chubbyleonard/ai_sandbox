import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import 'ai_service.dart';
import 'db_helper.dart';

// ---------------------------------------------------------
// CUSTOM MARKDOWN BUILDER FOR CODE BLOCKS
// ---------------------------------------------------------
class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CodeBlockBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final codeText = element.textContent;
    
    // If it's just short inline code within a sentence, let Flutter use default text styling
    if (!codeText.contains('\n')) return null; 
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF090A0F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar with Copy Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Code Snippet', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w600)),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: codeText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Code copied!'),
                        backgroundColor: const Color(0xFF3B82F6),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                      )
                    );
                  },
                  child: Row(
                    children: [
                      Icon(Icons.copy, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text('Copy', style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The Actual Code
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: SelectableText(
              codeText, 
              style: TextStyle(fontFamily: 'Courier', fontSize: 14, color: Colors.greenAccent[400], height: 1.5)
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// MAIN APP
// ---------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarBrightness: Brightness.dark));
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
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        fontFamily: 'SF Pro Display',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          surface: Color(0xFF12131A),
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

  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _sessions = [];
  String _currentSessionId = '';
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final sessions = await DatabaseHelper.instance.getSessions();
    setState(() {
      _sessions = sessions;
    });
    if (sessions.isNotEmpty) {
      _loadSession(sessions.first['id']);
    } else {
      _createNewSession();
    }
  }

  Future<void> _createNewSession() async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      _currentSessionId = newId;
      _messages.clear();
    });
  }

  Future<void> _loadSession(String sessionId) async {
    final history = await DatabaseHelper.instance.fetchMessages(sessionId);
    setState(() {
      _currentSessionId = sessionId;
      _messages = history.map((e) => Map<String, dynamic>.from(e)).toList();
    });
    _scrollToBottom();
  }

  Future<void> _deleteSession(String sessionId) async {
    await DatabaseHelper.instance.deleteSession(sessionId);
    await _loadSessions();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  void _sendMessage() async {
    final prompt = _textController.text.trim();
    if (prompt.isEmpty || _isGenerating) return;

    if (_messages.isEmpty) {
      final title = prompt.length > 25 ? '${prompt.substring(0, 25)}...' : prompt;
      await DatabaseHelper.instance.createSession(_currentSessionId, title);
      _loadSessions(); 
    }

    await DatabaseHelper.instance.saveMessage(_currentSessionId, 'user', prompt, '');

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
      await for (var chunk in _aiService.streamPrompt(prompt, _currentSessionId)) {
        setState(() {
          _messages[aiMessageIndex]['thinking'] = chunk['thinking'] ?? '';
          _messages[aiMessageIndex]['output'] = chunk['output'] ?? '';
        });
        finalThinking = chunk['thinking'] ?? '';
        finalOutput = chunk['output'] ?? '';
        _scrollToBottom();
      }
    } catch (e) {
      finalOutput = "Connection Error: $e";
      setState(() {
        _messages[aiMessageIndex]['output'] = finalOutput;
      });
    }

    await DatabaseHelper.instance.saveMessage(_currentSessionId, 'ai', finalOutput, finalThinking);

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
        backgroundColor: const Color(0xFF161821),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: const Text('Network Routing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ipController,
          decoration: InputDecoration(
            labelText: 'Tailscale IP',
            labelStyle: const TextStyle(color: Colors.grey),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1)), borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF3B82F6)), borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              await prefs.setString('server_ip', ipController.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Brain', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, letterSpacing: 0.5)),
        centerTitle: true,
        backgroundColor: const Color(0xFF090A0F),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.grey, size: 22), onPressed: _openNetworkSettings),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF12131A),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
                    foregroundColor: const Color(0xFF3B82F6),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: const Color(0xFF3B82F6).withOpacity(0.3))),
                  ),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('New Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  onPressed: () {
                    _createNewSession();
                    Navigator.pop(context);
                  },
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('RECENT SESSIONS', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
              Expanded(
                child: _sessions.isEmpty
                    ? Center(child: Text('No history.', style: TextStyle(color: Colors.grey[700])))
                    : ListView.builder(
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          final isActive = session['id'] == _currentSessionId;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                            tileColor: isActive ? Colors.white.withOpacity(0.03) : null,
                            leading: Icon(Icons.chat_bubble_outline, color: isActive ? const Color(0xFF3B82F6) : Colors.grey[600], size: 18),
                            title: Text(session['title'] ?? 'New Chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 15, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                              onPressed: () => _deleteSession(session['id']),
                            ),
                            onTap: () {
                              _loadSession(session['id']);
                              Navigator.pop(context);
                            },
                          );
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
                        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF161821), border: Border.all(color: Colors.white.withOpacity(0.05))), child: const Icon(Icons.memory, size: 48, color: Color(0xFF3B82F6))),
                        const SizedBox(height: 24),
                        const Text('Private Brain Ready', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('Unrestricted Local Intelligence', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['role'] == 'user';

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              gradient: isUser ? const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF4F46E5)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                              color: isUser ? null : const Color(0xFF161821),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(20),
                                topRight: const Radius.circular(20),
                                bottomLeft: Radius.circular(isUser ? 20 : 6),
                                bottomRight: Radius.circular(isUser ? 6 : 20),
                              ),
                              border: isUser ? null : Border.all(color: Colors.white.withOpacity(0.05)),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            child: isUser
                                ? Text(msg['output'] ?? '', style: const TextStyle(fontSize: 16, color: Colors.white, height: 1.5, letterSpacing: 0.2))
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (msg['thinking'] != null && msg['thinking'].isNotEmpty)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(color: const Color(0xFF090A0F), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.03))),
                                          child: Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              iconColor: Colors.grey,
                                              collapsedIconColor: Colors.grey,
                                              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                                              title: Row(
                                                children: [
                                                  const Icon(Icons.psychology_outlined, size: 16, color: Colors.grey),
                                                  const SizedBox(width: 8),
                                                  Text('Reasoning Process', style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w600)),
                                                ],
                                              ),
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                                                  child: Text(msg['thinking'], style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5, fontStyle: FontStyle.italic)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (msg['output'] != null && msg['output'].isNotEmpty) ...[
                                        MarkdownBody(
                                          data: msg['output'],
                                          selectable: true,
                                          builders: {
                                            'code': CodeBlockBuilder(context),
                                          },
                                          onTapLink: (text, href, title) async {
                                            if (href != null && await canLaunchUrl(Uri.parse(href))) {
                                              await launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                                            }
                                          },
                                          styleSheet: MarkdownStyleSheet(
                                            p: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 16, height: 1.6),
                                            code: TextStyle(backgroundColor: const Color(0xFF090A0F), fontFamily: 'Courier', fontSize: 14, color: Colors.greenAccent[400]),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ] else if (_isGenerating && index == _messages.length - 1)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6))),
                                            const SizedBox(width: 12),
                                            Text('Analyzing...', style: TextStyle(color: Colors.grey[500], fontSize: 14, fontWeight: FontWeight.w500)),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(color: const Color(0xFF090A0F), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFF161821), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.1))),
                      child: TextField(
                        controller: _textController,
                        maxLines: 5,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                        decoration: const InputDecoration(hintText: 'Ask Private Brain...', hintStyle: TextStyle(color: Colors.grey), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF4F46E5)]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: IconButton(
                      icon: _isGenerating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
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