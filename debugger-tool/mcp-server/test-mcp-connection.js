/**
 * Test MCP connection to AutoHotkey debugger
 *
 * Usage:
 *   1. Start MCP server: node build/index.js
 *   2. Start AutoHotkey: AutoHotkey.exe /Debug test_script.ahk
 *   3. Run this test: node test-mcp-connection.js
 */

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { spawn } from 'child_process';

async function testMCPConnection() {
  console.log('Starting MCP client test...\n');

  // Spawn the MCP server
  const serverProcess = spawn('node', ['build/index.js'], {
    stdio: ['pipe', 'pipe', 'inherit'],
  });

  const transport = new StdioClientTransport({
    command: 'node',
    args: ['build/index.js'],
  });

  const client = new Client(
    {
      name: 'test-client',
      version: '1.0.0',
    },
    {
      capabilities: {},
    }
  );

  try {
    await client.connect(transport);
    console.log('✓ Connected to MCP server\n');

    // List available tools
    console.log('=== Available Tools ===');
    const tools = await client.listTools();
    tools.tools.forEach((tool) => {
      console.log(`  ${tool.name}: ${tool.description}`);
    });
    console.log();

    // List available resources
    console.log('=== Available Resources ===');
    const resources = await client.listResources();
    resources.resources.forEach((resource) => {
      console.log(`  ${resource.uri}: ${resource.name}`);
    });
    console.log();

    // Try getting status
    console.log('=== Testing debug_status ===');
    try {
      const result = await client.callTool({
        name: 'debug_status',
        arguments: {},
      });
      console.log('Status result:', result.content[0].text);
    } catch (error) {
      console.log('Status error (expected if AHK not connected):', error.message);
    }
    console.log();

    // Try reading a resource
    console.log('=== Testing ahk://status resource ===');
    try {
      const resource = await client.readResource({
        uri: 'ahk://status',
      });
      console.log('Resource content:', resource.contents[0].text);
    } catch (error) {
      console.log('Resource error (expected if AHK not connected):', error.message);
    }
    console.log();

    console.log('✓ All tests completed!');
    console.log('\nNote: Some errors are expected if AutoHotkey is not connected.');
    console.log('To fully test, run: AutoHotkey.exe /Debug test_script.ahk');

  } catch (error) {
    console.error('Test failed:', error);
  } finally {
    await client.close();
    serverProcess.kill();
  }
}

testMCPConnection().catch(console.error);
