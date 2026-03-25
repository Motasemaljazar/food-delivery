import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/api.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key, required this.api, required this.state});
  final ApiClient api;
  final AppState state;

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  bool loading = true;
  String? error;
  List<dynamic> threads = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if(widget.state.customerId==null){ setState((){loading=false; threads=[];}); return; }
    setState((){loading=true; error=null;});
    try{
      threads = await widget.api.listComplaints(widget.state.customerId!);
    }catch(e){ error=e.toString(); }
    finally{ if(mounted) setState(()=>loading=false); }
  }

  Future<void> _newThread() async {
    final titleC = TextEditingController();
    final msgC = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_)=>AlertDialog(
      title: const Text('New complaint'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleC, decoration: const InputDecoration(labelText:'Title')),
        TextField(controller: msgC, decoration: const InputDecoration(labelText:'Message')),
      ]),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Cancel')), ElevatedButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Send'))],
    ));
    if(ok!=true) return;
    final id = await widget.api.createComplaint(customerId: widget.state.customerId!, title: titleC.text.trim(), message: msgC.text.trim());
    await _load();
    if(mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_)=>ComplaintThreadScreen(api: widget.api, threadId: id)));
  }

  @override
  Widget build(BuildContext context) {
    if(loading) return const Center(child: CircularProgressIndicator());
    if(error!=null) return Center(child: Text(error!));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: Text('Support chat', style: Theme.of(context).textTheme.titleMedium)),
              ElevatedButton.icon(onPressed: _newThread, icon: const Icon(Icons.add), label: const Text('New'))
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if(threads.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No messages'))),
                ...threads.map((t){
                  final m = t as Map<String, dynamic>;
                  return Card(
                    child: ListTile(
                      title: Text('#${m['id']} - ${m['title']}'),
                      subtitle: Text('Order: ${m['orderId'] ?? '-'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: ()=>Navigator.of(context).push(MaterialPageRoute(builder: (_)=>ComplaintThreadScreen(api: widget.api, threadId: m['id'] as int))),
                    ),
                  );
                })
              ],
            ),
          ),
        )
      ],
    );
  }
}

class ComplaintThreadScreen extends StatefulWidget {
  const ComplaintThreadScreen({super.key, required this.api, required this.threadId});
  final ApiClient api;
  final int threadId;

  @override
  State<ComplaintThreadScreen> createState() => _ComplaintThreadScreenState();
}

class _ComplaintThreadScreenState extends State<ComplaintThreadScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? thread;
  final msgC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState((){loading=true; error=null;});
    try{
      thread = await widget.api.getComplaint(widget.threadId);
    }catch(e){ error=e.toString(); }
    finally{ if(mounted) setState(()=>loading=false); }
  }

  Future<void> send() async {
    final txt = msgC.text.trim();
    if(txt.isEmpty) return;
    await widget.api.sendComplaintMessage(widget.threadId, fromAdmin: false, message: txt);
    msgC.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if(loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if(error!=null) return Scaffold(appBar: AppBar(), body: Center(child: Text(error!)));
    final msgs = (thread?['messages'] as List<dynamic>? ?? []).cast<Map<String,dynamic>>();

    return Scaffold(
      appBar: AppBar(title: Text('Thread #${widget.threadId}')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: msgs.map((m){
                final fromAdmin = m['fromAdmin'] as bool? ?? false;
                return Align(
                  alignment: fromAdmin ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: fromAdmin ? Colors.grey.shade200 : Colors.orange.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(m['message'].toString()),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: TextField(controller: msgC, decoration: const InputDecoration(hintText:'Type message...'))),
                const SizedBox(width: 8),
                IconButton(onPressed: send, icon: const Icon(Icons.send))
              ],
            ),
          )
        ],
      ),
    );
  }
}
