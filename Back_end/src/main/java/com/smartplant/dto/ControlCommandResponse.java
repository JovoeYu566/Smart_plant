package com.smartplant.dto;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class ControlCommandResponse {

    private String requestId;
    private String action;
    private String topic;
    private boolean success;
    private String message;
}
