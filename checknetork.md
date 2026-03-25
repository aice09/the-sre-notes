Yes — here is a compatible Ansible 2.7 style playbook for your requirement.

It will:
	•	check network hardware info
	•	list all available interfaces
	•	detect bond interfaces
	•	if bond exists, list bond name and IP
	•	detect InfiniBand-style interfaces
	•	collect IP info per interface
	•	export report to CSV or TXT
	•	allow export format selection using -e export_format=csv or txt

⸻

Files you need

Use this structure:

network_audit.yml
templates/network_report.csv.j2
templates/network_report.txt.j2
reports/
inventory.ini


⸻

1) Inventory sample

[kube]
server01 ansible_host=10.10.10.11
server02 ansible_host=10.10.10.12

[kube:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3

If your group is different, just replace kube.

⸻

2) Playbook: network_audit.yml

---
- name: Audit server network interfaces, bond, IB, and export report
  hosts: kube
  gather_facts: no
  become: yes

  vars:
    export_format: "csv"
    report_dir: "./reports"

  tasks:
    - name: Gather minimal facts only
      setup:
        gather_subset:
          - min
          - network

    - name: Get hardware vendor
      shell: cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown
      register: hw_vendor
      changed_when: false
      ignore_errors: yes

    - name: Get hardware product
      shell: cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown
      register: hw_product
      changed_when: false
      ignore_errors: yes

    - name: Get hardware serial
      shell: cat /sys/class/dmi/id/product_serial 2>/dev/null || echo unknown
      register: hw_serial
      changed_when: false
      ignore_errors: yes

    - name: Get all interface names
      shell: ls /sys/class/net
      register: all_ports_cmd
      changed_when: false

    - name: Set all ports fact
      set_fact:
        all_ports: "{{ all_ports_cmd.stdout_lines | default([]) }}"

    - name: Detect bond interfaces
      shell: ls /proc/net/bonding 2>/dev/null
      register: bond_list_cmd
      changed_when: false
      failed_when: false

    - name: Set bond interface list
      set_fact:
        bond_ports: "{{ bond_list_cmd.stdout_lines | default([]) if bond_list_cmd.rc == 0 else [] }}"

    - name: Detect InfiniBand-like interfaces
      set_fact:
        ib_ports: "{{ all_ports | select('match', '^(ib|ibp|mlx|enp.*ib.*)') | list }}"

    - name: Initialize interface report list
      set_fact:
        interface_report: []

    - name: Collect per-interface details
      shell: |
        DEV="{{ item }}"
        TYPE="unknown"
        MAC="$(cat /sys/class/net/${DEV}/address 2>/dev/null || echo '')"
        STATE="$(cat /sys/class/net/${DEV}/operstate 2>/dev/null || echo '')"
        SPEED="$(cat /sys/class/net/${DEV}/speed 2>/dev/null || echo '')"

        if [ -d "/sys/class/net/${DEV}/bonding" ]; then
          TYPE="bond"
        elif [ -d "/sys/class/net/${DEV}/device/infiniband" ]; then
          TYPE="infiniband"
        elif [ -L "/sys/class/net/${DEV}" ]; then
          TYPE="ethernet"
        fi

        IPV4="$(ip -4 -o addr show dev ${DEV} 2>/dev/null | awk '{print $4}' | paste -sd ';' -)"
        IPV6="$(ip -6 -o addr show dev ${DEV} 2>/dev/null | awk '{print $4}' | paste -sd ';' -)"

        if [ -f "/proc/net/bonding/${DEV}" ]; then
          SLAVES="$(awk -F': ' '/Slave Interface/ {print $2}' /proc/net/bonding/${DEV} | paste -sd ';' -)"
        else
          SLAVES=""
        fi

        echo "${DEV}|${TYPE}|${STATE}|${MAC}|${SPEED}|${IPV4}|${IPV6}|${SLAVES}"
      args:
        executable: /bin/bash
      loop: "{{ all_ports }}"
      register: interface_details_cmd
      changed_when: false

    - name: Build interface report structure
      set_fact:
        interface_report: "{{ interface_report + [ {
          'name': item.stdout.split('|')[0],
          'type': item.stdout.split('|')[1],
          'state': item.stdout.split('|')[2],
          'mac': item.stdout.split('|')[3],
          'speed': item.stdout.split('|')[4],
          'ipv4': item.stdout.split('|')[5],
          'ipv6': item.stdout.split('|')[6],
          'slaves': item.stdout.split('|')[7]
        } ] }}"
      loop: "{{ interface_details_cmd.results }}"

    - name: Build bond summary
      set_fact:
        bond_summary: "{{ interface_report | selectattr('type', 'equalto', 'bond') | list }}"

    - name: Build IB summary
      set_fact:
        ib_summary: "{{ interface_report | selectattr('type', 'equalto', 'infiniband') | list }}"

    - name: Ensure local report directory exists
      delegate_to: localhost
      become: no
      file:
        path: "{{ report_dir }}"
        state: directory
        mode: "0755"

    - name: Export per-host CSV report
      delegate_to: localhost
      become: no
      template:
        src: "templates/network_report.csv.j2"
        dest: "{{ report_dir }}/{{ inventory_hostname }}_network_report.csv"
      when: export_format == "csv"

    - name: Export per-host TXT report
      delegate_to: localhost
      become: no
      template:
        src: "templates/network_report.txt.j2"
        dest: "{{ report_dir }}/{{ inventory_hostname }}_network_report.txt"
      when: export_format == "txt"

    - name: Show summary
      debug:
        msg:
          - "Host={{ inventory_hostname }}"
          - "All ports={{ all_ports | join(', ') }}"
          - "Bond ports={{ bond_ports | join(', ') if bond_ports|length > 0 else 'none' }}"
          - "IB ports={{ ib_ports | join(', ') if ib_ports|length > 0 else 'none' }}"


⸻

3) CSV template: templates/network_report.csv.j2

hostname,vendor,product,serial,interface,type,state,mac,speed,ipv4,ipv6,bond_slaves
{% for iface in interface_report %}
{{ inventory_hostname }},{{ hw_vendor.stdout | default('unknown') | replace(',', ' ') }},{{ hw_product.stdout | default('unknown') | replace(',', ' ') }},{{ hw_serial.stdout | default('unknown') | replace(',', ' ') }},{{ iface.name }},{{ iface.type }},{{ iface.state }},{{ iface.mac }},{{ iface.speed }},{{ iface.ipv4 | replace(',', ';') }},{{ iface.ipv6 | replace(',', ';') }},{{ iface.slaves | replace(',', ';') }}
{% endfor %}


⸻

4) TXT template: templates/network_report.txt.j2

Host: {{ inventory_hostname }}
Vendor: {{ hw_vendor.stdout | default('unknown') }}
Product: {{ hw_product.stdout | default('unknown') }}
Serial: {{ hw_serial.stdout | default('unknown') }}

All Interfaces:
{% for iface in interface_report %}
- Name: {{ iface.name }}
  Type: {{ iface.type }}
  State: {{ iface.state }}
  MAC: {{ iface.mac }}
  Speed: {{ iface.speed }}
  IPv4: {{ iface.ipv4 }}
  IPv6: {{ iface.ipv6 }}
  Bond Slaves: {{ iface.slaves }}
{% endfor %}

Bond Interfaces:
{% if bond_summary | length > 0 %}
{% for bond in bond_summary %}
- {{ bond.name }} | IPv4={{ bond.ipv4 }} | Slaves={{ bond.slaves }}
{% endfor %}
{% else %}
- none
{% endif %}

InfiniBand Interfaces:
{% if ib_summary | length > 0 %}
{% for ib in ib_summary %}
- {{ ib.name }} | IPv4={{ ib.ipv4 }} | MAC={{ ib.mac }}
{% endfor %}
{% else %}
- none
{% endif %}


⸻

5) How to run

Export as CSV

ansible-playbook -i inventory.ini network_audit.yml -e export_format=csv

Export as TXT

ansible-playbook -i inventory.ini network_audit.yml -e export_format=txt

Reports will be saved under:

./reports/

Example:

reports/server01_network_report.csv
reports/server02_network_report.csv

or

reports/server01_network_report.txt


⸻

6) Important notes

This is designed to be safe for your older Ansible.

I intentionally used:
	•	gather_facts: no
	•	setup: gather_subset
	•	shell with simple Linux commands
	•	delegate_to: localhost for report export

because full facts can hit your earlier udevadm info timeout.

⸻

7) What it detects

For each host, it tries to identify:
	•	all visible interfaces from /sys/class/net
	•	whether interface is a bond
	•	whether interface looks like InfiniBand
	•	MAC address
	•	state
	•	speed
	•	IPv4 / IPv6
	•	bond slaves
	•	hardware vendor/product/serial

⸻

8) Optional improvement

If you want, I can make version 2 that produces one combined CSV for all servers instead of one file per host.