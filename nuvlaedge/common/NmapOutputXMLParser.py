from xml.etree import ElementTree
import logging

logger: logging.Logger = logging.getLogger(__name__)


class NmapOutputXMLParser:
    """
        XML parser for parsing the xml output
        of nmap commmand for getting all the details of
        the modbus devices.
    """

    def __init__(self, file):
        self.filename = file
        self.root = None

    def parse(self):
        self.root = ElementTree.parse(self.filename).getroot()

    def get_modbus_details(self) -> dict:
        """ Uses the output from the nmap port scan to find modbus
            services.
            Plain output example:

                PORT    STATE SERVICE
                502/tcp open  modbus
                | modbus-discover:
                |   sid 0x64:
                |     Slave ID data: \xFA\xFFPM710PowerMeter
                |     Device identification: Schneider Electric PM710 v03.110
                |   sid 0x96:
                |_    error: GATEWAY TARGET DEVICE FAILED TO RESPONSE

            :returns List of modbus devices"""
        if not self.root.attrib['args'].__contains__('modbus'):
            return {}
        hosts = self.__get_modbus_hosts()
        modbus_details = {}
        for host in hosts:
            modbus_details[host] = self.__get_modbus_port_details(host)
        return modbus_details

    def __get_modbus_hosts(self) -> []:
        """
            Get all the host addresses
        :return: A list of host addresses
        """
        hosts = []
        for host_addr in self.root.findall('host'):
            hosts.append(host_addr.find('address').attrib['addr'])
        return hosts

    def __get_modbus_port_details(self, host) -> []:
        """
            Get all details for the ports related to modbus
        :param host:
        :return: list of (key, value) pairs
        """
        ports = []
        for port_id in self.root.findall(f'.//host/address[@addr = \'{host}\']/..//port'
                                         '/service[@name = \'modbus\']/..'):
            attributes = port_id.attrib
            port_details = {
                "interface": attributes['protocol'].upper() if "protocol" in attributes else None,
                "port": int(attributes['portid']) if "portid" in attributes else None,
                "available": True if port_id.find('state').attrib['state'] == "open" else False
            }
            self.__get_port_identifiers(port_id, port_details)
            ports.append(port_details)
        return ports

    @staticmethod
    def __get_port_identifiers(port_ele: ElementTree.Element, details: dict):
        """
        Collect all the slave identifiers from the table section

        :param port_ele: Port element in the xml tree
        :param details: dict that needs to be filled
        :return:
        """
        details['identifiers'] = []
        for ids in port_ele.findall('.//table'):
            _id: str = ids.attrib['key']
            details['identifiers'].append(int(_id.split()[1], 16))
