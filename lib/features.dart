import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Copied to clipboard')),
  );
}

void duplicateConfig(
    BuildContext context, Map<String, dynamic> config, dynamic state) {
  state.setState(() {
    state.editingId = null;
    state.siteNameController.text = '${config['siteName']} (copy)';
    state.hostnameController.text = config['hostname'];
    state.usernameController.text = config['username'];
    state.portController.text = config['port'];
    state.usePassword = config['usePassword'] == 1;
    state.passwordController.text = config['password'];
    state.keyPathController.text = config['keyPath'];
    state.groupController.text = config['groupName'];
  });
  DefaultTabController.of(context).animateTo(0);
}
