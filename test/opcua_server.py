import asyncio
import random
from asyncua import Server, ua

async def main():
    # Initialize the server
    server = Server()
    await server.init()
    
    # Set the endpoint URL (binds to localhost on default OPC UA port 4840)
    endpoint = "opc.tcp://127.0.0.1:4840/freeopcua/server/"
    server.set_endpoint(endpoint)
    
    # Set server name (optional)
    server.set_server_name("Python OPC UA Simulation Server")

    # Set up a custom namespace
    uri = "http://github.io"
    idx = await server.register_namespace(uri)

    # Get the reference to the main 'Objects' folder node
    objects_node = server.get_objects_node()

    # Create a new object folder for your device/facility
    device_obj = await objects_node.add_object(idx, "MyDevice")

    # Add a variable (Temperature) to the device folder
    # We initialize it with a default value of 25.0
    temperature_var = await device_obj.add_variable(idx, "Temperature", 25.0)
    
    # Make the variable writable by clients
    await temperature_var.set_writable()

    print(f"OPC UA Server is running at: {endpoint}")
    print("Press Ctrl+C to stop the server.")

    # Start the server context block
    async with server:
        while True:
            # Simulate a fluctuating temperature value
            current_temp = round(random.uniform(20.0, 30.0), 2)
            
            # Update the variable's value on the server
            await temperature_var.write_value(current_temp)
            
            print(f"Updated Temperature Node Value: {current_temp}°C")
            
            # Wait for 1 second before the next update
            await asyncio.sleep(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer stopped successfully.")
