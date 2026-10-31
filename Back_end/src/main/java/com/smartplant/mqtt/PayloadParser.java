package com.smartplant.mqtt;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartplant.dto.PlantPayload;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class PayloadParser {

    private final ObjectMapper objectMapper;

    public PlantPayload parse(String json) throws Exception {
        PlantPayload payload = objectMapper.readValue(json, PlantPayload.class);
        if (payload != null) {
            payload.normalizeNewSchema();
        }
        return payload;
    }
}
