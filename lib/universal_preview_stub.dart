import 'package:flutter/material.dart';

Widget buildUniversalStrategyPreview({
  required String source,
  required bool isRemote,
}) {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.widgets_outlined, size: 56, color: Color(0xFF475569)),
          SizedBox(height: 16),
          Text(
            '当前平台未启用全能型插件',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 10),
          Text(
            'universal_file_viewer 不参与当前平台的构建，已回退为说明卡片。请切换到自由组合方案继续预览。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    ),
  );
}
