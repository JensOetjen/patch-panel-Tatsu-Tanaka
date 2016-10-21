# Software patch-panel.
class PatchPanel < Trema::Controller
  def start(_args)
    @patch = Hash.new { |hash,key| hash[key]=[] }
    @mirror_patch = Hash.new { |hash,key| hash[key]=[]  }
    logger.info 'PatchPanel started.'
  end

  def switch_ready(dpid)
    @patch[dpid].each do |port_a, port_b|
      delete_flow_entries dpid, port_a, port_b
      add_flow_entries dpid, port_a, port_b
    end
    @mirror_patch[dpid].each do |monitor_port, mirror_port|
      delete_flow_entries dpid, monitor_port, mirror_port
      add_flow_entries dpid, monitor_port, mirror_port
    end
  end

  def create_patch(dpid, port_a, port_b)
    add_flow_entries dpid, port_a, port_b
    @patch[dpid] << [port_a, port_b].sort
  end

  def delete_patch(dpid, port_a, port_b)
    delete_flow_entries dpid, port_a, port_b
    @patch[dpid] -= [port_a, port_b].sort
  end

  def create_mirror_patch(dpid, monitor_port, mirror_port)
    add_mirror_flow_entries dpid, monitor_port, mirror_port
    @mirror_patch[dpid] << [monitor_port, mirror_port]
  end

  def list_patch(dpid)
    list = Array.new()
    list << @patch
    list << @mirror_patch
    return list
  end

  private

  def add_flow_entries(dpid, port_a, port_b)
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_a),
                      actions: SendOutPort.new(port_b))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_b),
                      actions: SendOutPort.new(port_a))
  end

  def delete_flow_entries(dpid, port_a, port_b)
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_a))
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_b))
  end

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

end
