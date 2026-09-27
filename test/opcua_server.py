import asyncio
from asyncua import Server, ua

async def main():
    # Initialize the server
    server = Server()
    await server.init()
    
    # Set the endpoint URL (binds to localhost on default OPC UA port 4840)
    endpoint = "opc.tcp://127.0.0.1:4840/freeopcua/server/"
    server.set_endpoint(endpoint)
    
    # Set server name
    server.set_server_name("Python OPC UA Simulation Server")

    # Set up a custom namespace
    uri = "http://github.io"
    idx = await server.register_namespace(uri)

    # Get the reference to the main 'Objects' folder node
    objects_node = server.get_objects_node()

    # Create a new object folder for your device/facility
    device_obj = await objects_node.add_object(idx, "MyDevice")

    # Add a variable (Temperature) to the device folder
    temperature_var = await device_obj.add_variable(
        idx, "Temperature", val=22.0, varianttype=ua.VariantType.Float
    )
    # Make the variable writable by clients
    await temperature_var.set_writable()

    # Add a new variable (Valve Position) to the device folder (0.0 to 100.0%)
    valve_var = await device_obj.add_variable(
        idx, "Valve Position", val=0.0, varianttype=ua.VariantType.Float
    )
    # Make the variable writable by clients
    await valve_var.set_writable()

    print(f"OPC UA Server is running at: {endpoint}")
    print("Press Ctrl+C to stop the server.")

    # Simulation Physics Parameters
    room_temp = 22.0       # Base temperature when valve is fully closed
    max_heating = 80.0     # Maximum potential temperature addition when valve is 100% open
    thermal_inertia = 0.1  # Lower value = slower, smoother temperature changes

    # Start the server context block
    async with server:
        while True:
            # 1. Read the current valve position (which can be changed dynamically by a client)
            current_valve_raw = await valve_var.get_value()
            
            # Constrain valve position to a realistic 0 to 100% range
            valve_pos = max(0.0, min(100.0, float(current_valve_raw)))
            if current_valve_raw != valve_pos:
                await valve_var.write_value(ua.Variant(valve_pos, ua.VariantType.Float))

            # 2. Read the current temperature
            current_temp = float(await temperature_var.get_value())

            # 3. Calculate target temperature based on valve position
            # (e.g., 50% open means target temperature is room_temp + 40 degrees)
            target_temp = room_temp + ((valve_pos / 100.0) * max_heating)

            # 4. Smoothly step the temperature toward the target (First-order lag simulation)
            new_temp = current_temp + (thermal_inertia * (target_temp - current_temp))
            new_temp = round(new_temp, 2)

            # 5. Update the temperature node value on the server
            await temperature_var.write_value(ua.Variant(new_temp, ua.VariantType.Float))
            
            print(f"Valve Position: {valve_pos:5.1f}% | Target Temp: {target_temp:5.1f}°C | Current Temp: {new_temp:5.2f}°C")

            # Wait for 1 second before the next physics calculation step
            await asyncio.sleep(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer stopped successfully.")
