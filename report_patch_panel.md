#情報ネットワーク学演習II 10/19 レポート課題
===========
学籍番号 33E16011
提出者 田中 達也

##課題 (パッチパネルの機能拡張)

パッチパネルに機能を追加しよう。

授業で説明したパッチの追加と削除以外に、以下の機能をパッチパネルに追加してください。

1. ポートのミラーリング
2. パッチとポートミラーリングの一覧

それぞれ patch_panel のサブコマンドとして実装してください。

なお 1 と 2 以外にも機能を追加した人には、ボーナス点を加点します。

##解答
###1. ポートのミラーリング
ポートミラーリングとは、スイッチやルータの持つ機能の一つで、あるポートが送受信するデータを、同時に別のポートから送出する機能である。
監視されるポートを「モニターポート」と呼び、コピーが流れてくるポートを「ミラーポート」という。

ミラーリングを作成するサブコマンド`create_mirror`を用意するために、[./bin/patch_panel](https://github.com/handai-trema/patch-panel-Tatsu-Tanaka/blob/master/bin/patch_panel)に以下の実装を行う。
```
  desc 'Creates a mirror patch'
  arg_name 'dpid port mirror'
  command :create_mirror do |c|
    c.desc 'Location to find socket files'
    c.flag [:S, :socket_dir], default_value: Trema::DEFAULT_SOCKET_DIR

    c.action do |_global_options, options, args|
      dpid = args[0].hex
      monitor_port = args[1].to_i
      mirror_port = args[2].to_i
      Trema.trema_process('PatchPanel', options[:socket_dir]).controller.
        create_mirror_patch(dpid, monitor_port, mirror_port)
    end
  end
```
元のパッチパネルのプログラムに実装されていた`create`や`delete`の記述を参考に、monitor_portをモニターポート、mirror_portをミラーポートとして、[./lib/patch_panel.rb](https://github.com/handai-trema/patch-panel-Tatsu-Tanaka/blob/master/lib/patch_panel.rb)内で実装した`create_mirror_patch`メソッドを呼び出す。
サブコマンド実行時は、端末上で以下のコマンドを入力する。
```
./bin/patch_panel create_mirror (datapath ID) (モニターポート番号)　(ミラーポート番号)
```

ミラーリングの機能を提供するメソッドを[./lib/patch_panel.rb](https://github.com/handai-trema/patch-panel-Tatsu-Tanaka/blob/master/lib/patch_panel.rb)に追加する。
####create_mirror_patchメソッド
以下のメソッド`create_mirror_patch`を用意する。
```
  def create_mirror_patch(dpid, monitor_port, mirror_port)
    add_mirror_flow_entries dpid, monitor_port, mirror_port
    @mirror_patch[dpid] << [monitor_port, mirror_port]
  end
```
`create_patch`メソッドと同様に、一つのミラーパッチを書き込む`add_mirror_flow_entries`プライベートメソッドを呼び出す。
ミラーパッチ設定`@mirror_patch`にミラーパッチ情報を追加する。


####add_mirror_flow_entriesメソッド
以下の、一つのミラーパッチを書き込む`add_mirror_flow_entries`プライベートメソッドを呼び出す。
```
  def add_mirror_flow_entries(dpid, monitor_port, mirror_port)
    source_port = nil
    @patch[dpid].each do |port_a, port_b|
      if port_a == monitor_port then source_port = port_b
      elsif port_b == monitor_port then source_port = port_a
      end
    end
    if source_port == nil then return false
    end
    send_flow_mod_delete(dpid, match: Match.new(in_port: source_port))
    send_flow_mod_delete(dpid, match: Match.new(in_port: monitor_port))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: source_port),
                      actions: [
                        SendOutPort.new(monitor_port),
                        SendOutPort.new(mirror_port)
                      ])
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: monitor_port),
                      actions: [
                        SendOutPort.new(source_port),
                        SendOutPort.new(mirror_port)
                      ])
    return true
  end
```
監視したいモニターポートに対して受信されるパケットとモニターポートから送信されるパケットの両方をミラーポートに送信する必要がある。
前者の実現のためには、モニターポート宛に届くパケットの送信元ポートを特定する必要がある。
そのため、パッチパネルからモニターポートがパッチ情報に含まれているものを参照し、送信元ポートを特定する。
特定した送信元ポートが送信元として指定されているフローエントリを削除する。
また、モニターポートが送信元として指定されているフローエントリを削除する。
続いて、特定した送信元ポートに対して、パケットをモニターポートとミラーポートそれぞれにパケットを送るようにフローエントリを追加する。
また、モニターポートに対して、パケットを特定した元のポートとミラーポートそれぞれにパケットを送るようにフローエントリを追加する。

###2. パッチとポートミラーリングの一覧
パッチとポートミラーリングの状態を表示するサブコマンド`list`を用意した。
[./bin/patch_panel](https://github.com/handai-trema/patch-panel-Tatsu-Tanaka/blob/master/bin/patch_panel)に以下の実装を行う。
```
  desc 'Prints patch and mirror patch'
  arg_name 'dpid patchlist patch mirror_patch'
  command :list do |c|
    c.desc 'Location to find socket files'
    c.flag [:S, :socket_dir], default_value: Trema::DEFAULT_SOCKET_DIR

    c.action do |_global_options, options, args|
      dpid = args[0].hex
      patchlist = Trema.trema_process('PatchPanel', options[:socket_dir]).controller.
        list_patch(dpid)
      @patch = patchlist[0]
      @mirror_patch = patchlist[1]
      @patch[dpid].each do |port_a, port_b|
        print("Port ", port_a, " is connected to port ", port_b, "\n")
      end
      @mirror_patch[dpid].each do |monitor_port, mirror_port|
        print("Monitor port:", monitor_port, ", Mirror port:", mirror_port, "\n")
      end
    end
  end
```
すでに実装されていたサブコマンドは、./lib/patch_panel.rbでメソッドが実行されていたが、同様に実装してしまうと、サブコマンドを入力した端末と出力する端末が異なってしまい扱いづらくなる。
そのため、./bin/patch_panelでターミナルの表示を行う。
他のサブコマンドの記述を参考にした。
[./lib/patch_panel.rb](https://github.com/handai-trema/patch-panel-Tatsu-Tanaka/blob/master/lib/patch_panel.rb)内で実装した`list_patch`メソッドを呼び出し、返り値を`patchlist`に入れる。
[./lib/patch_panel.rb](https://github.com/handai-trema/patch-panel-Tatsu-Tanaka/blob/master/lib/patch_panel.rb)内で実装した`list_patch`メソッドは以下である。

```
  def list_patch(dpid)
    list = Array.new()
    list << @patch
    list << @mirror_patch
    return list
  end
```
パッチリストやミラーリングの情報は./lib/patch_panel.rbのインスタンス変数に保存されているため、@patch,@mirror_patchを配列`list`に入れて返すメソッドを用意した。

/bin/patch_panelにおいて、@patch,@mirror_patchそれぞれに対して、printメソッドを用いて、パッチ情報とミラーリング情報をターミナルに出力する。

このまま実行すると、port1とport2のパッチを作成し、サブコマンド`list`を実行すると以下のような出力になった。
```
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ ./bin/patch_panel create 0xabc 1 2
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ ./bin/patch_panel list 0xabc
1 is connected to 
2 is connected to 
```
ポート、1と2がセットでパッチとして登録されておらず、それぞれが単独でハッシュに登録されている。
@patchに正しく二次元配列として格納されていないと考えられるので、[./lib/patch_panel.rb](https://github.com/handai-trema/patch-panel-Tatsu-Tanaka/blob/master/lib/patch_panel.rb)内のstartハンドラを以下のように変更した。
```
  def start(_args)
    @patch = Hash.new { |hash,key| hash[key]=[] }
    @mirror_patch = Hash.new { |hash,key| hash[key]=[] }
    logger.info 'PatchPanel started.'
  end
```
[このページ](http://simanman.hatenablog.com/entry/2013/09/24/211044)を参考に、ハッシュのデフォルト値を配列にして初期化した。
またcreate_patchメソッドも以下のように変更した。
```
  def create_patch(dpid, port_a, port_b)
    add_flow_entries dpid, port_a, port_b
    @patch[dpid] << [port_a, port_b].sort
  end
```

###動作確認
まず端末を起動し、patch-panel-Tatsu-Tanakaディレクトリにおいて、`bundle exec trema run ./lib patch_panel.rb -c patcpanel.conf`を入力した。
別の端末を起動し、以下の手順で動作確認を行った。
1. ポート1とポート2のパッチを作成
1. パッチの一覧の表示
1. モニターポートをポート1,ミラーポートをポート3としてミラーリング
1. パッチの一覧の表示
1. host1からhost2へパケット送信
1. host2からhost1へパケット送信
1. host1,host2,host3のスタッツを確認し、パケット送信とミラーリングの確認
実行結果を以下に示す。
```
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ ./bin/patch_panel create 0xabc 1 2
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ ./bin/patch_panel list 0xabc
Port 1 is connected to port 2
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ ./bin/patch_panel create_mirror 0xabc 1 3
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ ./bin/patch_panel list 0xabc
Port 1 is connected to port 2
Monitor port:1, Mirror port:3
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ trema send_packets --source host1 --dest host2
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ trema send_packets --source host2 --dest host1
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ trema show_stats host1
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 1 packet
Packets received:
  192.168.0.2 -> 192.168.0.1 = 1 packet
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ trema show_stats host2
Packets sent:
  192.168.0.2 -> 192.168.0.1 = 1 packet
Packets received:
  192.168.0.1 -> 192.168.0.2 = 1 packet
ensyuu2@ensyuu2-VirtualBox:~/patch-panel-Tatsu-Tanaka$ trema show_stats host3
Packets received:
  192.168.0.1 -> 192.168.0.2 = 1 packet
  192.168.0.2 -> 192.168.0.1 = 1 packet
```
host1,host2でそれぞれ送受信ができていることと、ミラーポートに接続されているhost3に、モニターポートで送受信されたパケット情報を受け取っていることを確認できた。
ミラーポートに接続されているhost3は自分宛てのパケットではないためパケットを破棄してしまうため、[./lib/patch_panel.conf](https://github.com/handai-trema/patch-panel-Tatsu-Tanaka/blob/master/patch_panel.conf)において
```
vhost ('host3') { 
  ip '192.168.0.3' 
  promisc true
}
```
と記述し、host3のみをネットワークを流れるすべてのパケットを受信して読み込むモードに変更した。


##参考文献
デビッド・トーマス+アンドリュー・ハント(2001)「プログラミング Ruby」ピアソン・エデュケーション.  
[テキスト: 6章 "インテリジェントなパッチパネル"](http://yasuhito.github.io/trema-book/#patch_panel)
