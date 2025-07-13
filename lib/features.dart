import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sshconfiggenerator/main.dart';

void copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Copied to clipboard')),
  );
}

void duplicateConfig(BuildContext context, Map<String, dynamic> config) {
  final sshConfigGeneratorState =
      context.findAncestorStateOfType<_SSHConfigGeneratorState>();
  if (sshConfigGeneratorState != null) {
    sshConfigGeneratorState.setState(() {
      sshConfigGeneratorState.editingId = null;
      sshConfigGeneratorState.siteNameController.text =
          '${config['siteName']} (copy)';
      sshConfigGeneratorState.hostnameController.text = config['hostname'];
      sshConfigGeneratorState.usernameController.text = config['username'];
      sshConfigGeneratorState.portController.text = config['port'];
      sshConfigGeneratorState.usePassword = config['usePassword'] == 1;
      sshConfigGeneratorState.passwordController.text = config['password'];
      sshConfigGeneratorState.keyPathController.text = config['keyPath'];
      sshConfigGeneratorState.groupController.text = config['groupName'];
    });
    DefaultTabController.of(context)?.animateTo(0);
  }
}
