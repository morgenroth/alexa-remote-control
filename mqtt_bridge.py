#!/usr/bin/env python
#

import subprocess as sp
import json
import paho.mqtt.client as mqtt
import time

class EchoDevice:
    def __init__(self, name):
        self.name = name
        self.controls = {
            'play': self.play,
            'pause': self.pause,
            'next': self.next,
            'prev': self.prev,
            'forward': self.forward,
            'rewind': self.rewind,
            'shuffle': self.shuffle
        }

    def play(self, plist = None):
        if plist:
            self.playlist(plist)
        else:
            self.command("play")

    def pause(self):
        self.command("pause")

    def next(self):
        self.command("next")
        
    def prev(self):
        self.command("prev")
        
    def forward(self):
        self.command("fwd")
        
    def rewind(self):
        self.command("rwd")
        
    def shuffle(self):
        self.command("shuffle")

    def volume(self, level):
        self.command("vol:%d" % level)

    def command(self, cmd):
        result = sp.check_output(["/bin/sh", "alexa_remote_control.sh", "-d", self.name, "-e", cmd])

    def tune(self, station):
        result = sp.check_output(["/bin/sh", "alexa_remote_control.sh", "-d", self.name, "-u", station['seedId']])

    def playlist(self, pl):
        result = sp.check_output(["/bin/sh", "alexa_remote_control.sh", "-d", self.name, "-t", pl['asin']])


def find_station(keyword):
    ret = []
    result = sp.check_output(["/bin/sh", "alexa_remote_control.sh", "-S"])
    stations = json.loads(result[result.find('{'):])['primeStationSectionList'][0]
    for c in stations['categories']:
        for s in c['stations']:
            if (keyword.lower() in s['stationTitle'].lower()):
                ret.append(s)
    return ret


def find_playlist(keyword):
    ret = []
    data = sp.check_output(["/bin/sh", "alexa_remote_control.sh", "-P"])
    offset = 0
    decoder = json.JSONDecoder()

    while offset < len(data):
        try:
            offset = offset + data[offset:].find('{')
            obj, idx = decoder.raw_decode(data[offset:])
            offset = offset + idx

            try:
                for p in obj['primePlaylistList']:
                    if (keyword.lower() in p['title'].lower()):
                        ret.append(p)
            except KeyError, e:
                pass
        except ValueError, e:
            break

    return ret


def devices():
    ret = []
    result = sp.check_output(["/bin/sh", "alexa_remote_control.sh", "-a"])
    for name in result.splitlines()[1:]:
        ret.append(EchoDevice(name.decode('utf8')))
    return ret


def on_message(mqttc, devices, msg):
    cmd = msg.topic.split('/')
    if len(cmd) == 4:
        for d in devices:
            if d.name == cmd[2].decode('utf8'):
                if cmd[3] == 'control':
                    try:
                        d.controls[msg.payload]()
                        print("Device '%s' => %s" % (d.name, msg.payload))
                    except KeyError, e:
                        pass
                elif cmd[3] == 'playlist':
                    print("Search playlist with keyword '%s'" % msg.payload)
                    playlists = find_playlist(msg.payload)

                    pnames = list(p['title'] for p in playlists)
                    mqttc.publish("alexa/device/%s/playlists" % d.name, json.dumps(pnames))

                    if len(playlists) > 0:
                        print("Play '%s' on '%s'" % (playlists[0]['title'], d.name))
                        d.play(playlists[0])
                    else:
                        print("No playlist found.")
                elif cmd[3] == 'station':
                    print("Search station with keyword '%s'" % msg.payload)
                    stations = find_station(msg.payload)

                    # publish results
                    snames = list(s['stationTitle'] for s in stations)
                    mqttc.publish("alexa/device/%s/stations" % d.name, json.dumps(snames))

                    if len(stations) > 0:
                        print("Tune to station '%s' on '%s'" % (stations[0]['stationTitle'], d.name))
                        d.tune(stations[0])
                    else:
                        print("No station found.")
                elif cmd[3] == 'volume':
                    level = int(msg.payload)
                    print("Set volume of '%s' to %d" % (d.name, level))
                    d.volume(level)


def main():
    dlist = []

    # create MQTT client
    mqttc = mqtt.Client(clean_session=True, userdata=dlist)

    # assign callback and connect
    mqttc.on_message = on_message
    mqttc.connect("localhost", 1883, 60)

    # start MQTT loop
    mqttc.loop_start()

    # subscribe to control topics 
    mqttc.subscribe("alexa/device/#")

    while True:
        # broadcast available devices to 'alexa/devices'
        del dlist[:]
        dnames = []
        for d in devices():
            dlist.append(d)
            dnames.append(d.name)
        pubt = mqttc.publish("alexa/devices", payload=json.dumps(dnames), retain=True)
        pubt.wait_for_publish()
        print("Device list published")

        # wait for 5 minutes
        time.sleep(300.0)


if __name__ == "__main__":
    print("Running MQTT API bridge")
    try:
        main()
    except KeyboardInterrupt, e:
        pass