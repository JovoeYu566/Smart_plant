package com.smartplant.controller;

import com.smartplant.common.ApiResponse;
import com.smartplant.domain.entity.ControlCommandLog;
import com.smartplant.dto.ControlCommandRequest;
import com.smartplant.dto.ControlCommandResponse;
import com.smartplant.service.ControlService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/control")
@RequiredArgsConstructor
public class ControlController {

    private final ControlService controlService;

    @PostMapping("/command")
    public ApiResponse<ControlCommandResponse> command(@Valid @RequestBody ControlCommandRequest request,
                                                       Authentication authentication) {
        String operator = authentication != null ? authentication.getName() : "unknown";
        return ApiResponse.ok(controlService.send(request, operator));
    }

    @GetMapping("/history")
    public ApiResponse<List<ControlCommandLog>> history(@RequestParam(defaultValue = "30") int limit) {
        return ApiResponse.ok(controlService.history(limit));
    }
}
